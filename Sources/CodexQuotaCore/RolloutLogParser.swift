import Foundation

public struct RolloutTokenEvent: Equatable, Sendable {
    public var timestamp: Date
    public var lastTotalTokens: Int
    public var cumulativeTotalTokens: Int
    public var limitID: String?
    public var primary: RolloutRateLimitWindow?
    public var secondary: RolloutRateLimitWindow?

    public init(
        timestamp: Date,
        lastTotalTokens: Int,
        cumulativeTotalTokens: Int,
        limitID: String? = nil,
        primary: RolloutRateLimitWindow?,
        secondary: RolloutRateLimitWindow?
    ) {
        self.timestamp = timestamp
        self.lastTotalTokens = max(0, lastTotalTokens)
        self.cumulativeTotalTokens = max(0, cumulativeTotalTokens)
        self.limitID = limitID
        self.primary = primary
        self.secondary = secondary
    }

    public var duplicateKey: String {
        let milliseconds = Int((timestamp.timeIntervalSince1970 * 1_000).rounded())
        return "\(milliseconds)|\(lastTotalTokens)|\(cumulativeTotalTokens)|\(limitID ?? "")"
    }
}

public struct RolloutRateLimitWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public enum RolloutLogParser {
    private static let tokenCountNeedle = Data(#""token_count""#.utf8)

    public static func parseLine(_ line: String) -> RolloutTokenEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard line.contains("\"token_count\"") else {
            return nil
        }

        guard hasStringValue(for: "type", value: "event_msg", in: line),
              hasStringValue(for: "type", value: "token_count", in: line),
              let timestampRaw = stringValue(for: "timestamp", in: line),
              let timestamp = CodexDateParser.parseTimestamp(timestampRaw)
        else {
            return nil
        }

        let lastUsage = section(named: "last_token_usage", in: line)
        let totalUsage = section(named: "total_token_usage", in: line)
        let primary = rateLimitWindow(named: "primary", in: line, until: ["secondary"])
        let secondary = rateLimitWindow(named: "secondary", in: line, until: ["credits", "individual_limit", "plan_type", "rate_limit_reached_type"])
        let lastTotalTokens = lastUsage.flatMap { intValue(for: "total_tokens", in: $0) } ?? 0
        let cumulativeTotalTokens = totalUsage.flatMap { intValue(for: "total_tokens", in: $0) } ?? 0

        guard lastTotalTokens > 0 || cumulativeTotalTokens > 0 || primary != nil || secondary != nil else {
            return nil
        }

        return RolloutTokenEvent(
            timestamp: timestamp,
            lastTotalTokens: lastTotalTokens,
            cumulativeTotalTokens: cumulativeTotalTokens,
            limitID: stringValue(for: "limit_id", in: line),
            primary: primary,
            secondary: secondary
        )
    }

    public static func parseFile(at url: URL) -> [RolloutTokenEvent] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else {
            return []
        }

        var events: [RolloutTokenEvent] = []
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let range = data.range(of: tokenCountNeedle, options: [], in: searchStart..<data.endIndex) {
            let lineStart = lineStartIndex(containing: range.lowerBound, in: data)
            let lineEnd = lineEndIndex(containing: range.upperBound, in: data)
            if lineStart < lineEnd,
               let line = String(data: data[lineStart..<lineEnd], encoding: .utf8),
               let event = parseLine(line) {
                events.append(event)
            }

            if lineEnd >= data.endIndex {
                break
            }
            searchStart = lineEnd
        }

        return events
    }

    private static func lineStartIndex(containing index: Data.Index, in data: Data) -> Data.Index {
        var current = index
        while current > data.startIndex {
            let previous = data.index(before: current)
            let byte = data[previous]
            if byte == 10 || byte == 13 {
                return current
            }
            current = previous
        }
        return data.startIndex
    }

    private static func lineEndIndex(containing index: Data.Index, in data: Data) -> Data.Index {
        var current = index
        while current < data.endIndex {
            let byte = data[current]
            if byte == 10 || byte == 13 {
                return current
            }
            current = data.index(after: current)
        }
        return data.endIndex
    }

    private static func rateLimitWindow(named name: String, in text: String, until nextKeys: [String]) -> RolloutRateLimitWindow? {
        guard let windowText = section(named: name, in: text, until: nextKeys),
              let usedPercent = doubleValue(for: "used_percent", in: windowText),
              let windowMinutes = intValue(for: "window_minutes", in: windowText)
        else {
            return nil
        }

        let resetsAt = intValue(for: "resets_at", in: windowText)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return RolloutRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func section(named name: String, in text: String, until nextKeys: [String] = []) -> String? {
        guard let nameRange = text.range(of: "\"\(name)\"") else {
            return nil
        }

        let lowerBound = nameRange.upperBound
        var upperBound = text.endIndex
        for nextKey in nextKeys {
            if let nextRange = text[lowerBound...].range(of: "\"\(nextKey)\""),
               nextRange.lowerBound < upperBound {
                upperBound = nextRange.lowerBound
            }
        }

        return String(text[lowerBound..<upperBound])
    }

    private static func stringValue(for key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\""),
              let start = valueStart(after: keyRange.upperBound, in: text)
        else {
            return nil
        }

        return stringValue(startingAt: start, in: text)
    }

    private static func intValue(for key: String, in text: String) -> Int? {
        numericValue(for: key, in: text).flatMap(Int.init)
    }

    private static func doubleValue(for key: String, in text: String) -> Double? {
        numericValue(for: key, in: text).flatMap(Double.init)
    }

    private static func numericValue(for key: String, in text: String) -> String? {
        guard let start = valueStart(for: key, in: text) else {
            return nil
        }

        var index = start
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber || character == "." || character == "-" {
                value.append(character)
                index = text.index(after: index)
            } else {
                break
            }
        }

        return value.isEmpty ? nil : value
    }

    private static func valueStart(for key: String, in text: String) -> String.Index? {
        guard let keyRange = text.range(of: "\"\(key)\"") else {
            return nil
        }

        return valueStart(after: keyRange.upperBound, in: text)
    }

    private static func valueStart(after lowerBound: String.Index, in text: String) -> String.Index? {
        var index = lowerBound
        while index < text.endIndex {
            let character = text[index]
            if character == ":" || character.isWhitespace {
                index = text.index(after: index)
            } else {
                return index
            }
        }

        return nil
    }

    private static func hasStringValue(for key: String, value: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex

        while let keyRange = text.range(of: "\"\(key)\"", range: searchRange) {
            if let start = valueStart(after: keyRange.upperBound, in: text),
               stringValue(startingAt: start, in: text) == value {
                return true
            }

            searchRange = keyRange.upperBound..<text.endIndex
        }

        return false
    }

    private static func stringValue(startingAt start: String.Index, in text: String) -> String? {
        guard start < text.endIndex, text[start] == "\"" else {
            return nil
        }

        var index = text.index(after: start)
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                return value
            }
            value.append(character)
            index = text.index(after: index)
        }

        return nil
    }
}

private struct RolloutEnvelope: Decodable {
    var timestamp: Date
    var type: String
    var payload: RolloutPayload
    var rateLimits: RolloutRateLimits?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
        case rateLimits = "rate_limits"
    }
}

private struct RolloutPayload: Decodable {
    var type: String
    var info: RolloutTokenInfo?
    var rateLimits: RolloutRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
    }
}

private struct RolloutTokenInfo: Decodable {
    var totalTokenUsage: RolloutTokenUsage
    var lastTokenUsage: RolloutTokenUsage

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
        case lastTokenUsage = "last_token_usage"
    }
}

private struct RolloutTokenUsage: Decodable {
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
    }
}

private struct RolloutRateLimits: Decodable {
    var limitID: String?
    var primary: RolloutRateLimitWindowPayload?
    var secondary: RolloutRateLimitWindowPayload?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
    }
}

private struct RolloutRateLimitWindowPayload: Decodable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        windowMinutes = try container.decode(Int.self, forKey: .windowMinutes)

        if let resetSeconds = try container.decodeIfPresent(Double.self, forKey: .resetsAt) {
            resetsAt = Date(timeIntervalSince1970: resetSeconds)
        } else {
            resetsAt = nil
        }
    }
}
