import ArgumentParser

// MARK: - Entry Point

@main
struct SPPCtl: ParsableCommand {

    // MARK: Configuration

    static let configuration = CommandConfiguration(
        commandName: "sppctl",
        abstract: "Swift Playground++ Studio command-line tool",
        discussion: """
        sppctl lets you create, build, validate, and export .sppproject bundles
        from the command line. Use it in CI/CD pipelines or as a companion to
        the SPP Studio IDE.
        """,
        version: "1.0.0",
        subcommands: [
            BuildCommand.self,
            NewCommand.self,
            ValidateCommand.self,
            ExportCommand.self,
        ]
    )
}
