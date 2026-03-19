import Foundation

/// Utilities for WARC-Date field (W3C profile of ISO 8601, UTC, per WARC spec section 5.3).
public enum WARCDate: Sendable {

    private static let formatterFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static let formatterFractional: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        return f
    }()

    /// Formats a Date as a WARC-Date string (YYYY-MM-DDThh:mm:ssZ).
    public static func string(from date: Date) -> String {
        formatterFull.string(from: date)
    }

    /// Parses a WARC-Date string. Returns nil for unrecognised formats.
    public static func date(from string: String) -> Date? {
        if let d = formatterFractional.date(from: string) { return d }
        if let d = formatterFull.date(from: string) { return d }
        // Fallback for partial timestamps (e.g. "2016-01")
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        return iso.date(from: string)
    }
}
