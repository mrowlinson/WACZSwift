import Foundation
import Testing
import ZIPFoundation

@testable import WACZSwift

@Suite("WACZValidator Integration")
struct WACZValidatorTests {
    func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "warc.gz", subdirectory: "Fixtures") else {
            throw WACZError.fileNotFound("Fixtures/sample.warc.gz")
        }
        return url
    }

    func createValidWACZ() throws -> URL {
        let input = try fixtureURL()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wacz")
        let options = WACZCreatorOptions(inputs: [input], output: output)
        try WACZCreator().create(options: options)
        return output
    }

    @Test("Valid WACZ passes validation")
    func validWACZ() throws {
        let wacz = try createValidWACZ()
        defer { try? FileManager.default.removeItem(at: wacz) }

        let validator = WACZValidator()
        let result = try validator.validate(at: wacz)

        #expect(result.isValid, "Errors: \(result.errors)")
    }

    @Test("Missing datapackage.json fails validation")
    func missingDatapackage() throws {
        let wacz = try createValidWACZ()
        defer { try? FileManager.default.removeItem(at: wacz) }

        // Create a WACZ without datapackage.json
        let corruptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wacz")
        defer { try? FileManager.default.removeItem(at: corruptedURL) }

        // Copy and remove datapackage.json
        let sourceArchive = Archive(url: wacz, accessMode: .read)!
        let destArchive = Archive(url: corruptedURL, accessMode: .create)!

        for entry in sourceArchive where entry.path != "datapackage.json" && entry.path != "datapackage-digest.json" {
            var entryData = Data()
            _ = try sourceArchive.extract(entry) { data in
                entryData.append(data)
            }
            try destArchive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entryData.count),
                compressionMethod: entry.isCompressed ? .deflate : .none,
                provider: { position, size in
                    entryData[Int(position)..<Int(position) + size]
                }
            )
        }

        let validator = WACZValidator()
        let result = try validator.validate(at: corruptedURL)

        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("datapackage.json") })
    }

    @Test("Invalid ZIP file fails")
    func invalidZIP() throws {
        let badFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wacz")
        defer { try? FileManager.default.removeItem(at: badFile) }

        try Data("not a zip file".utf8).write(to: badFile)

        let validator = WACZValidator()
        let result = try validator.validate(at: badFile)

        #expect(!result.isValid)
    }
}
