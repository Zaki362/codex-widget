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
    public static func parseLine(_ line: String) -> RolloutTokenEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = line.data(using: .utf8) else {
            return nil
        }

        do {
            let envelope = try decoder.decode(RolloutEnvelope.self, from: data)
            guard envelope.type == "event_msg", envelope.payload.type == "token_count" else {
                return nil
            }

            let info = envelope.payload.info
            let rateLimits = envelope.rateLimits ?? envelope.payload.rateLimits
            guard info != nil || rateLimits != nil else {
                return nil
            }

            let primary = rateLimits?.primary.map { window in
                RolloutRateLimitWindow(
                    usedPercent: window.usedPercent,
                    windowMinutes: window.windowMinutes,
                    resetsAt: window.resetsAt
                )
            }
            let secondary = rateLimits?.secondary.map { window in
                RolloutRateLimitWindow(
                    usedPercent: window.usedPercent,
                    windowMinutes: window.windowMinutes,
                    resetsAt: window.resetsAt
                )
            }

            return RolloutTokenEvent(
                timestamp: envelope.timestamp,
                lastTotalTokens: info?.lastTokenUsage.totalTokens ?? 0,
                cumulativeTotalTokens: info?.totalTokenUsage.totalTokens ?? 0,
                limitID: rateLimits?.limitID,
                primary: primary,
                secondary: secondary
            )
        } catch {
            return nil
        }
    }

    public static func parseFile(at url: URL) -> [RolloutTokenEvent] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            parseLine(String(line))
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if let parsed = CodexDateParser.parseTimestamp(rawValue) {
                return parsed
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Codex timestamp: \(rawValue)"
            )
        }
        return decoder
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
