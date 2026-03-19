import ArgumentParser
import Foundation
import WACZSwift

struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a WACZ file from WARC archives"
    )

    @Argument(help: "Input WARC file(s)")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output WACZ file path")
    var output: String = "output.wacz"

    @Option(name: [.short, .customLong("hash-type")], help: "Hash algorithm (sha256 or md5)")
    var hashType: String = "sha256"

    @Option(name: .shortAndLong, help: "Title for the WACZ archive")
    var title: String?

    @Option(name: [.customLong("desc")], help: "Description for the WACZ archive")
    var desc: String?

    @Option(name: .shortAndLong, help: "Main page URL")
    var url: String?

    @Option(name: [.customLong("ts")], help: "Main page date (ISO 8601)")
    var timestamp: String?

    @Option(name: .shortAndLong, help: "Custom pages JSONL file")
    var pages: String?

    @Flag(name: [.customLong("copy-pages")], help: "Copy pages from WARC metadata")
    var copyPages: Bool = false

    @Option(name: [.customLong("extra-pages")], help: "Extra pages JSONL file")
    var extraPages: String?

    @Option(name: .shortAndLong, help: "Log directory to include")
    var logDirectory: String?

    @Flag(name: [.short, .customLong("text")], help: "Extract text from HTML pages")
    var extractText: Bool = false

    @Option(name: [.customLong("split-seeds")], help: "Seed URLs for page splitting (comma-separated)")
    var splitSeeds: String?

    @Option(name: [.customLong("signing-url")], help: "URL of signing server")
    var signingURL: String?

    @Option(name: [.customLong("signing-token")], help: "Auth token for signing server")
    var signingToken: String?

    func run() throws {
        let inputURLs = inputs.map { URL(fileURLWithPath: $0) }
        let outputURL = URL(fileURLWithPath: output)

        guard let ht = HashType(rawValue: hashType) else {
            throw ValidationError("Invalid hash type: \(hashType). Use 'sha256' or 'md5'.")
        }

        let seeds = splitSeeds?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let options = WACZCreatorOptions(
            inputs: inputURLs,
            output: outputURL,
            hashType: ht,
            title: title,
            description: desc,
            mainPageURL: url,
            mainPageDate: timestamp,
            customPages: pages.map { URL(fileURLWithPath: $0) },
            copyPages: copyPages,
            extraPages: extraPages.map { URL(fileURLWithPath: $0) },
            logDirectory: logDirectory.map { URL(fileURLWithPath: $0) },
            extractText: extractText,
            splitSeeds: seeds,
            signingURL: signingURL.flatMap { URL(string: $0) },
            signingToken: signingToken
        )

        let creator = WACZCreator()
        try creator.create(options: options)

        print("Created WACZ file: \(outputURL.path)")
    }
}
