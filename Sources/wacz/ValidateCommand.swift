import ArgumentParser
import Foundation
import WACZSwift

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate a WACZ file"
    )

    @Option(name: .shortAndLong, help: "WACZ file to validate")
    var file: String

    @Flag(name: [.customLong("verify-auth")], help: "Verify cryptographic signature")
    var verifyAuth: Bool = false

    @Option(name: [.customLong("verifier-url")], help: "URL of signature verification server")
    var verifierURL: String?

    func run() throws {
        let fileURL = URL(fileURLWithPath: file)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ValidationError("File not found: \(file)")
        }

        let validator = WACZValidator()
        let result = try validator.validate(
            at: fileURL,
            verifyAuth: verifyAuth,
            verifierURL: verifierURL.flatMap { URL(string: $0) }
        )

        for warning in result.warnings {
            print("WARNING: \(warning)")
        }

        if result.isValid {
            print("VALID: \(file)")
        } else {
            print("INVALID: \(file)")
            for error in result.errors {
                print("  ERROR: \(error)")
            }
            throw ExitCode.failure
        }
    }
}
