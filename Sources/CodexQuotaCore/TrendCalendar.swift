import Foundation

public enum TrendCalendar {
    public static func lastFiveDayStarts(now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (-4...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func shortLabel(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%02d-%02d", month, day)
    }

    public static func resetLabel(for date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "--" }

        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    public static func compactTokenLabel(_ tokens: Int) -> String {
        let absolute = max(0, tokens)
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(absolute) / 1_000_000)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", Double(absolute) / 1_000)
        }
        return "\(absolute)"
    }
}

public enum CodexDateParser {
    public static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
