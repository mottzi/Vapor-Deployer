import Vapor

/// Installs Swift using Swiftly if it's not already present, and verifies the installed version.
struct SwiftStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Installing Swift via Swiftly"

    func run() async throws {

        if !isSwiftlyInstalled {
            try await installSwiftly()
        }
        
        try await printSwiftVersion()
    }

}

extension SwiftStep {

    private func installSwiftly() async throws {

        let workdir = try await shell.runAsServiceUser("mktemp", ["-d"], environment: userEnvironment).trimmed
        defer { try? FileManager.default.removeItem(atPath: workdir) }

        let arch = try await shell.runAsServiceUser("uname", ["-m"], environment: userEnvironment).trimmed
        let archive = "swiftly-\(arch).tar.gz"
        
        try await shell.runAsServiceUser(
            "curl",
            ["-fL", "-o", archive, "https://download.swift.org/swiftly/linux/\(archive)"],
            directory: workdir,
            environment: userEnvironment
        )
        
        try await shell.runAsServiceUser("tar", ["zxf", archive], directory: workdir, environment: userEnvironment)
        
        try await shell.runAsServiceUser(
            "./swiftly",
            ["init", "--quiet-shell-followup", "--assume-yes"],
            directory: workdir,
            environment: userEnvironment
        )
    }

    private func printSwiftVersion() async throws {
        let version = try await shell.runAsServiceUser(swiftBinary, ["--version"], environment: userEnvironment)
        console.print(version.trimmed)
    }

}

extension SwiftStep {

    private var swiftBinary: String {
        "\(paths.swiftlyBinDirectory)/swift"
    }

    private var userEnvironment: [String: String] {
        ["HOME": paths.serviceHome, "USER": context.serviceUser]
    }

    private var isSwiftlyInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: swiftBinary)
    }

}
