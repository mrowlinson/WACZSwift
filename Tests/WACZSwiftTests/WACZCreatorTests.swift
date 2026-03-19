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
}

import ZIPFoundation
