import Foundation

private let cdxjDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMddHHmmss"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// Convert a Date to a 14-digit CDXJ timestamp (e.g., "20230101120000")
public func cdxjTimestamp(from date: Date) -> String {
    cdxjDateFormatter.string(from: date)
}

/// Parse a 14-digit CDXJ timestamp back to a Date
public func parseTimestamp(_ string: String) -> Date? {
    cdxjDateFormatter.date(from: string)
}

/// Convert a Date to an ISO 8601 string for pages/datapackage
public func isoDate(from date: Date) -> String {
    WARCDate.string(from: date)
}

/// Convert a 14-digit timestamp to ISO date string
public func timestampToISODate(_ timestamp: String) -> String? {
    guard let date = parseTimestamp(timestamp) else { return nil }
    return isoDate(from: date)
}

/// Current UTC time formatted as ISO 8601
public func nowISO() -> String {
    WARCDate.string(from: Date())
}
