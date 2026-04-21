import Vapor
import Foundation

struct SwiftStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Installing Swift via Swiftly"

    func run() async throws {
        let swiftBinary = "\(paths.swiftlyBinDirectory)/swift"
        let userEnvironment = ["HOME": paths.serviceHome, "USER": context.serviceUser]

        if !FileManager.default.isExecutableFile(atPath: swiftBinary) {
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

        let version = try await shell.runAsServiceUser(swiftBinary, ["--version"], environment: userEnvironment)
        console.print(version.trimmed)
    }

}
