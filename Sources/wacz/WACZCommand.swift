import ArgumentParser

@main
struct WACZCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wacz",
        abstract: "Create and validate WACZ (Web Archive Collection Zipped) files",
        version: "0.1.0",
        subcommands: [CreateCommand.self, ValidateCommand.self]
    )
}
