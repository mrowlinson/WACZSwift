import Foundation
import Testing

@testable import WACZSwift

@Suite("CDXIndexer")
struct CDXIndexerTests {
    func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "warc.gz", subdirectory: "Fixtures") else {
            throw WACZError.fileNotFound("Fixtures/sample.warc.gz")
        }
        return url
    }

    @Test("Index WARC produces CDX entries")
    func indexWARC() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        // Should have 3 response records
        #expect(entries.count == 3)
    }

    @Test("CDX entries are sorted by SURT")
    func sortedBySURT() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        for i in 1..<entries.count {
            #expect(entries[i - 1].surt <= entries[i].surt)
        }
    }

    @Test("CDX entry has correct SURT for example.com")
    func correctSURT() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        let mainEntry = entries.first { $0.url == "http://example.com/" }
        #expect(mainEntry != nil)
        #expect(mainEntry!.surt == "com,example)/")
    }

    @Test("CDXJ line format")
    func cdxjLineFormat() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        let line = entries[0].toCDXJLine()
        #expect(line.hasPrefix("com,example)"))
        #expect(line.contains("\"url\""))
        #expect(line.contains("\"mime\""))
        #expect(line.contains("\"status\""))
        #expect(line.hasSuffix("\n"))
    }

    @Test("Generate compressed CDX")
    func compressedCDX() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let compressed = try indexer.generateCompressedCDX(from: [url])

        // Should be non-empty gzip data
        #expect(compressed.count > 0)
        // Gzip magic bytes
        #expect(compressed[0] == 0x1F)
        #expect(compressed[1] == 0x8B)
    }

    @Test("HTML responses have correct MIME type")
    func htmlMIMEType() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        let htmlEntry = entries.first { $0.url == "http://example.com/" }
        #expect(htmlEntry?.mime == "text/html")
        #expect(htmlEntry?.status == "200")
    }

    @Test("JSON response has correct MIME type")
    func jsonMIMEType() throws {
        let url = try fixtureURL()
        let indexer = CDXIndexer()
        let entries = try indexer.indexWARC(at: url)

        let jsonEntry = entries.first { $0.url == "http://example.com/api/status" }
        #expect(jsonEntry?.mime == "application/json")
    }
}
