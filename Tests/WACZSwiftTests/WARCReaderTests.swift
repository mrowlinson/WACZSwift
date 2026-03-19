import Foundation
import Testing

@testable import WACZSwift

@Suite("WARCReader")
struct WARCReaderTests {
    func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "warc.gz", subdirectory: "Fixtures") else {
            throw WACZError.fileNotFound("Fixtures/sample.warc.gz")
        }
        return url
    }

    @Test("Read all records from fixture")
    func readAllRecords() throws {
        let url = try fixtureURL()
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()

        #expect(results.count == 3)
    }

    @Test("First record is HTTP response")
    func firstRecordType() throws {
        let url = try fixtureURL()
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()

        let first = results[0]
        #expect(first.record.recordType == .response)
        #expect(first.record.targetURI == "http://example.com/")
        #expect(first.filename == "sample.warc.gz")
        #expect(first.offset == 0)
    }

    @Test("Parse HTTP content from response record")
    func parseHTTPContent() throws {
        let url = try fixtureURL()
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()

        let http = results[0].record.parseHTTPContent()
        #expect(http != nil)
        #expect(http!.statusCode == 200)
        #expect(http!.headers["content-type"]?.contains("text/html") == true)
        #expect(http!.body.count > 0)
    }

    @Test("Records have sequential offsets")
    func sequentialOffsets() throws {
        let url = try fixtureURL()
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()

        for i in 1..<results.count {
            #expect(results[i].offset == results[i - 1].offset + results[i - 1].length)
        }
    }

    @Test("Record dates are parsed correctly")
    func recordDates() throws {
        let url = try fixtureURL()
        let reader = try WARCReader(url: url)
        let results = try reader.readRecords()

        #expect(results[0].record.date != nil)
        let dateStr = formatWARCDate(results[0].record.date!)
        #expect(dateStr == "2024-01-15T10:30:00Z")
    }
}
