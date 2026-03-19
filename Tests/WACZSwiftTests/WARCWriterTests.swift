import Foundation
import Testing

@testable import WACZSwift

@Suite("WARCWriter")
struct WARCWriterTests {
    @Test("Write and read back a response record (compressed)")
    func roundTripCompressed() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let outputURL = tmpDir.appendingPathComponent("roundtrip-\(UUID().uuidString).warc.gz")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<html><body>Hello</body></html>"
        let block = Data(httpResponse.utf8)
        let recordID = WARCRecord.generateRecordID()
        let dateStr = "2024-06-15T12:00:00Z"

        let headers: [String: String] = [
            "WARC-Type": "response",
            "WARC-Record-ID": recordID,
            "WARC-Date": dateStr,
            "Content-Length": String(block.count),
            "Content-Type": "application/http;msgtype=response",
            "WARC-Target-URI": "http://example.com/",
        ]

        let record = WARCRecord(headers: headers, contentBlock: block)

        let writer = try WARCWriter(path: outputURL, compress: true)
        try writer.write(record)
        try writer.close()

        // Read it back
        let reader = try WARCReader(url: outputURL)
        let results = try reader.readRecords()

        #expect(results.count == 1)
        let readBack = results[0].record
        #expect(readBack.recordType == .response)
        #expect(readBack.recordID == recordID)
        #expect(readBack.targetURI == "http://example.com/")
        #expect(readBack.contentBlock == block)

        let http = readBack.parseHTTPContent()
        #expect(http != nil)
        #expect(http!.statusCode == 200)
        #expect(http!.body == Data("<html><body>Hello</body></html>".utf8))
    }

    @Test("Write multiple records and read back")
    func multipleRecords() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let outputURL = tmpDir.appendingPathComponent("multi-\(UUID().uuidString).warc.gz")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writer = try WARCWriter(path: outputURL, compress: true)

        // Write warcinfo record
        let warcinfoBlock = Data("software: WACZSwift\r\n".utf8)
        let warcinfoRecord = WARCRecord(
            headers: [
                "WARC-Type": "warcinfo",
                "WARC-Record-ID": WARCRecord.generateRecordID(),
                "WARC-Date": "2024-06-15T12:00:00Z",
                "Content-Type": "application/warc-fields",
                "Content-Length": String(warcinfoBlock.count),
            ],
            contentBlock: warcinfoBlock
        )
        try writer.write(warcinfoRecord)

        // Write response record
        let httpResponse = "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot Found"
        let responseBlock = Data(httpResponse.utf8)
        let responseRecord = WARCRecord(
            headers: [
                "WARC-Type": "response",
                "WARC-Record-ID": WARCRecord.generateRecordID(),
                "WARC-Date": "2024-06-15T12:00:01Z",
                "Content-Type": "application/http;msgtype=response",
                "WARC-Target-URI": "http://example.com/missing",
                "Content-Length": String(responseBlock.count),
            ],
            contentBlock: responseBlock
        )
        try writer.write(responseRecord)
        try writer.close()

        // Read back
        let reader = try WARCReader(url: outputURL)
        let results = try reader.readRecords()

        #expect(results.count == 2)
        #expect(results[0].record.recordType == .warcinfo)
        #expect(results[1].record.recordType == .response)
        #expect(results[1].record.targetURI == "http://example.com/missing")

        let http = results[1].record.parseHTTPContent()
        #expect(http?.statusCode == 404)
    }

    @Test("Record ID generation produces valid format")
    func generateRecordID() {
        let id = WARCRecord.generateRecordID()
        #expect(id.hasPrefix("<urn:uuid:"))
        #expect(id.hasSuffix(">"))
        #expect(id.count > 20)
    }
}
