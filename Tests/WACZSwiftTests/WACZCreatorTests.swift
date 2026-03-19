import Foundation
import Testing

@testable import WACZSwift

@Suite("WACZCreator Integration")
struct WACZCreatorTests {
    func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "warc.gz", subdirectory: "Fixtures") else {
            throw WACZError.fileNotFound("Fixtures/sample.warc.gz")
        }
        return url
    }

    func tempOutput() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wacz")
    }

    @Test("Create WACZ from fixture")
    func createWACZ() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(
            inputs: [input],
            output: output,
            title: "Test Archive",
            description: "A test WACZ file"
        )

        let creator = WACZCreator()
        try creator.create(options: options)

        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("Created WACZ contains required files")
    func containsRequiredFiles() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(inputs: [input], output: output)
        try WACZCreator().create(options: options)

        let archive = ZIPFoundation.Archive(url: output, accessMode: .read)!
        let paths = Set(archive.map { $0.path })

        #expect(paths.contains("datapackage.json"))
        #expect(paths.contains("datapackage-digest.json"))
        #expect(paths.contains("indexes/index.cdx"))
        #expect(paths.contains("pages/pages.jsonl"))
        #expect(paths.contains("archive/sample.warc.gz"))
    }

    @Test("Created WACZ validates successfully")
    func createdWACZValidates() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(inputs: [input], output: output)
        try WACZCreator().create(options: options)

        let validator = WACZValidator()
        let result = try validator.validate(at: output)

        #expect(result.isValid, "Validation errors: \(result.errors)")
    }

    @Test("Create with text extraction")
    func withTextExtraction() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(
            inputs: [input],
            output: output,
            extractText: true
        )
        try WACZCreator().create(options: options)

        // Read pages.jsonl from the WACZ
        let archive = ZIPFoundation.Archive(url: output, accessMode: .read)!
        let pagesEntry = archive.first { $0.path == "pages/pages.jsonl" }!
        var pagesData = Data()
        _ = try archive.extract(pagesEntry) { data in
            pagesData.append(data)
        }

        let text = String(data: pagesData, encoding: .utf8)!
        #expect(text.contains("hasText"))
    }

    @Test("Create with MD5 hash type")
    func withMD5() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(
            inputs: [input],
            output: output,
            hashType: .md5
        )
        try WACZCreator().create(options: options)

        // Read datapackage.json and check hash prefix
        let archive = ZIPFoundation.Archive(url: output, accessMode: .read)!
        let dpEntry = archive.first { $0.path == "datapackage.json" }!
        var dpData = Data()
        _ = try archive.extract(dpEntry) { data in
            dpData.append(data)
        }

        let dp = try JSONDecoder().decode(Datapackage.self, from: dpData)
        let firstHash = dp.resources.first!.hash
        #expect(firstHash.hasPrefix("md5:"))
    }

    @Test("Datapackage has correct metadata")
    func datapackageMetadata() throws {
        let input = try fixtureURL()
        let output = tempOutput()
        defer { try? FileManager.default.removeItem(at: output) }

        let options = WACZCreatorOptions(
            inputs: [input],
            output: output,
            title: "My Archive",
            description: "Test description",
            mainPageURL: "http://example.com/",
            mainPageDate: "2024-01-15T10:30:00Z"
        )
        try WACZCreator().create(options: options)

        let archive = ZIPFoundation.Archive(url: output, accessMode: .read)!
        let dpEntry = archive.first { $0.path == "datapackage.json" }!
        var dpData = Data()
        _ = try archive.extract(dpEntry) { data in
            dpData.append(data)
        }

        let dp = try JSONDecoder().decode(Datapackage.self, from: dpData)
        #expect(dp.title == "My Archive")
        #expect(dp.description == "Test description")
        #expect(dp.mainPageURL == "http://example.com/")
        #expect(dp.wacz_version == "1.1.1")
    }

    // MARK: - Diagnostic: Response record pipeline

    @Test("WACZ from response records has correct CDX, pages, and offsets")
    func createWACZWithResponseRecords() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wacz-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let warcFile = tmpDir.appendingPathComponent("data.warc.gz")
        let output = tmpDir.appendingPathComponent("output.wacz")
        let articleURL = "https://test.example/article"
        let imageURL = "https://test.example/article/image-1.jpg"
        let dateStr = "2025-06-15T12:00:00Z"

        // --- Build a .warc.gz identical to AppleNewsExtractor's output ---
        let writer = try WARCWriter(path: warcFile, compress: true)

        // 1. warcinfo
        let infoBody = "software: TestSuite\r\n".data(using: .utf8)!
        try writer.write(WARCRecord(
            headers: [
                "WARC-Type": "warcinfo",
                "WARC-Record-ID": WARCRecord.generateRecordID(),
                "WARC-Date": dateStr,
                "Content-Length": "\(infoBody.count)",
                "Content-Type": "application/warc-fields",
            ],
            contentBlock: infoBody
        ))

        // 2. HTML response
        let htmlBody = "<html><head><title>Test Article</title></head><body><p>Hello world</p></body></html>".data(using: .utf8)!
        let htmlHTTP = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(htmlBody.count)\r\n\r\n"
        var htmlBlock = htmlHTTP.data(using: .utf8)!
        htmlBlock.append(htmlBody)
        try writer.write(WARCRecord(
            headers: [
                "WARC-Type": "response",
                "WARC-Record-ID": WARCRecord.generateRecordID(),
                "WARC-Date": dateStr,
                "WARC-Target-URI": articleURL,
                "Content-Length": "\(htmlBlock.count)",
                "Content-Type": "application/http;msgtype=response",
            ],
            contentBlock: htmlBlock
        ))

        // 3. Image response (small synthetic JPEG-like payload)
        let imageBody = Data(repeating: 0xFF, count: 64)
        let imgHTTP = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(imageBody.count)\r\n\r\n"
        var imgBlock = imgHTTP.data(using: .utf8)!
        imgBlock.append(imageBody)
        try writer.write(WARCRecord(
            headers: [
                "WARC-Type": "response",
                "WARC-Record-ID": WARCRecord.generateRecordID(),
                "WARC-Date": dateStr,
                "WARC-Target-URI": imageURL,
                "Content-Length": "\(imgBlock.count)",
                "Content-Type": "application/http;msgtype=response",
            ],
            contentBlock: imgBlock
        ))

        try writer.close()

        // --- Create WACZ ---
        let options = WACZCreatorOptions(
            inputs: [warcFile],
            output: output,
            title: "Diagnostic Test",
            mainPageURL: articleURL,
            mainPageDate: dateStr
        )
        try WACZCreator().create(options: options)

        let archive = ZIPFoundation.Archive(url: output, accessMode: .read)!

        // === CDX assertions ===
        let cdxEntry = archive.first { $0.path == "indexes/index.cdx" }
        #expect(cdxEntry != nil, "indexes/index.cdx must exist")

        var cdxData = Data()
        _ = try archive.extract(cdxEntry!) { cdxData.append($0) }
        let cdxText = String(data: cdxData, encoding: .utf8)!
        let cdxLines = cdxText.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(cdxLines.count == 2, "CDX should have 2 entries (warcinfo skipped), got \(cdxLines.count):\n\(cdxText)")

        // Parse each CDX line: "{surt} {timestamp} {json}"
        for line in cdxLines {
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            #expect(parts.count == 3, "CDX line should have 3 parts: \(line)")

            let json = try JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as! [String: String]
            #expect(json["status"] == "200", "Status should be 200: \(line)")
            #expect(json["filename"] == "data.warc.gz", "Filename should be bare WARC name (no archive/ prefix): \(line)")

            let offset = Int(json["offset"]!)!
            let length = Int(json["length"]!)!
            #expect(offset >= 0, "Offset must be non-negative")
            #expect(length > 0, "Length must be positive")

            // Verify we can actually decompress the gzip member at the recorded offset
            let warcData = try Data(contentsOf: warcFile)
            #expect(offset + length <= warcData.count,
                    "offset(\(offset)) + length(\(length)) exceeds file size(\(warcData.count))")
            let (decompressed, consumed) = try Gzip.decompressMember(from: warcData, offset: offset)
            #expect(consumed == length,
                    "Gzip consumed \(consumed) bytes but CDX says length=\(length)")
            #expect(!decompressed.isEmpty, "Decompressed data should not be empty")

            // Verify the decompressed data contains the expected URL in WARC headers
            // Search for the URL as raw bytes (body may contain non-text data)
            let url = json["url"]!
            let urlBytes = Data(url.utf8)
            #expect(decompressed.range(of: urlBytes) != nil,
                    "Decompressed record should contain URL \(url)")
        }

        // Check that one entry is for the article and one for the image
        let cdxURLs = cdxLines.compactMap { line -> String? in
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let json = try? JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: String] else { return nil }
            return json["url"]
        }
        #expect(cdxURLs.contains(articleURL), "CDX should contain article URL")
        #expect(cdxURLs.contains(imageURL), "CDX should contain image URL")

        // === Pages assertions ===
        let pagesEntry = archive.first { $0.path == "pages/pages.jsonl" }
        #expect(pagesEntry != nil, "pages/pages.jsonl must exist")

        var pagesData = Data()
        _ = try archive.extract(pagesEntry!) { pagesData.append($0) }
        let pagesText = String(data: pagesData, encoding: .utf8)!
        let pagesLines = pagesText.components(separatedBy: "\n").filter { !$0.isEmpty }

        // First line is the header, remaining lines are pages
        #expect(pagesLines.count >= 2, "pages.jsonl should have header + at least 1 page, got \(pagesLines.count):\n\(pagesText)")

        let pageEntries = pagesLines.dropFirst()
        #expect(pageEntries.count == 1, "Should have exactly 1 page (HTML only, not image), got \(pageEntries.count)")

        if let firstPage = pageEntries.first,
           let pageJSON = try? JSONSerialization.jsonObject(with: Data(firstPage.utf8)) as? [String: Any] {
            #expect(pageJSON["url"] as? String == articleURL,
                    "Page URL should be \(articleURL), got \(pageJSON["url"] ?? "nil")")
        }

        // === Datapackage assertions ===
        let dpEntry = archive.first { $0.path == "datapackage.json" }!
        var dpData = Data()
        _ = try archive.extract(dpEntry) { dpData.append($0) }
        let dp = try JSONDecoder().decode(Datapackage.self, from: dpData)

        #expect(dp.mainPageURL == articleURL, "mainPageUrl should match article URL")
        #expect(dp.title == "Diagnostic Test")

        // Every resource path must exist in the ZIP
        let zipPaths = Set(archive.map { $0.path })
        for resource in dp.resources {
            #expect(zipPaths.contains(resource.path),
                    "Resource path \(resource.path) not found in ZIP")
        }

        // === ZIP compression assertions ===
        for entry in archive {
            if entry.path.hasSuffix(".warc.gz") {
                #expect(!entry.isCompressed, "WARC should use STORE, not DEFLATE: \(entry.path)")
            }
        }
    }

}

import ZIPFoundation
