import Vapor
import Foundation

struct SwiftlyStep: SetupStep {

    let title = "Installing Swift via Swiftly"

    func run(context: SetupContext, console: any Console) async throws {
        let paths = try context.requirePaths()
        let swiftBinary = "\(paths.swiftlyBinDirectory)/swift"
        let userEnvironment = ["HOME": paths.serviceHome, "USER": context.serviceUser]

        if !FileManager.default.isExecutableFile(atPath: swiftBinary) {
            let workdir = try await SetupUserShell.runAsServiceUser(context, ["mktemp", "-d"], environment: userEnvironment).trimmed
            defer { try? FileManager.default.removeItem(atPath: workdir) }

            let arch = try await SetupUserShell.runAsServiceUser(context, ["uname", "-m"], environment: userEnvironment).trimmed
            let archive = "swiftly-\(arch).tar.gz"
            try await SetupUserShell.runAsServiceUser(
                context,
                ["curl", "-fL", "-o", archive, "https://download.swift.org/swiftly/linux/\(archive)"],
                directory: workdir,
                environment: userEnvironment
            )
            try await SetupUserShell.runAsServiceUser(context, ["tar", "zxf", archive], directory: workdir, environment: userEnvironment)
            try await SetupUserShell.runAsServiceUser(
                context,
                ["./swiftly", "init", "--quiet-shell-followup", "--assume-yes"],
                directory: workdir,
                environment: userEnvironment
            )
        }

        let version = try await SetupUserShell.runAsServiceUser(context, [swiftBinary, "--version"], environment: userEnvironment)
        console.print(version.trimmed)
    }

}
