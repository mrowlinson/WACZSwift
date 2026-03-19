import Foundation
import Testing

@testable import WACZSwift

@Suite("Timestamps")
struct TimestampTests {
    @Test("Parse WARC date")
    func parseWARC() {
        let date = WARCDate.date(from: "2024-01-15T10:30:00Z")
        #expect(date != nil)

        let formatted = WARCDate.string(from: date!)
        #expect(formatted == "2024-01-15T10:30:00Z")
    }

    @Test("CDXJ timestamp format")
    func cdxjFormat() {
        let date = WARCDate.date(from: "2024-01-15T10:30:00Z")!
        let ts = cdxjTimestamp(from: date)
        #expect(ts == "20240115103000")
    }

    @Test("Timestamp to ISO date")
    func timestampToISO() {
        let result = timestampToISODate("20240115103000")
        #expect(result == "2024-01-15T10:30:00Z")
    }

    @Test("Parse 14-digit timestamp")
    func parseTS() {
        let date = parseTimestamp("20240115103000")
        #expect(date != nil)
        let formatted = WARCDate.string(from: date!)
        #expect(formatted == "2024-01-15T10:30:00Z")
    }

    @Test("ISO date roundtrip")
    func isoRoundtrip() {
        let date = WARCDate.date(from: "2024-06-01T00:00:00Z")!
        let iso = isoDate(from: date)
        #expect(iso == "2024-06-01T00:00:00Z")
    }
}
