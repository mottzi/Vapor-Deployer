import Vapor
import Foundation

struct BuildStep: SetupStep {

    let title = "Building deployer and target app"

    func run(context: SetupContext, console: any Console) async throws {
        let paths = try context.requirePaths()
        let env = ["HOME": paths.serviceHome, "USER": context.serviceUser, "PATH": paths.swiftPath]
        let swift = "\(paths.swiftlyBinDirectory)/swift"

        if context.buildFromSource {
            console.print("Building deployer in \(context.deployerBuildMode) mode...")
            try await UserShell.runAsServiceUserStreamingTail(context, [swift, "build", "-c", context.deployerBuildMode], directory: paths.installDirectory, environment: env)
            let binDir = try await UserShell.runAsServiceUser(
                context,
                [swift, "build", "-c", context.deployerBuildMode, "--show-bin-path"],
                directory: paths.installDirectory,
                environment: env
            ).trimmed
            let binary = "\(binDir)/deployer"
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                throw SetupCommand.Error.invalidValue("deployer binary", "expected binary was not produced at '\(binary)'")
            }
            try await UserShell.runAsServiceUser(context, ["install", "-m", "0755", binary, paths.deployerBinary], environment: env)
        }

        console.print("Building target app in \(context.appBuildMode) mode...")
        try await UserShell.runAsServiceUserStreamingTail(context, [swift, "build", "-c", context.appBuildMode], directory: paths.appDirectory, environment: env)
        let appBinDir = try await UserShell.runAsServiceUser(
            context,
            [swift, "build", "-c", context.appBuildMode, "--show-bin-path"],
            directory: paths.appDirectory,
            environment: env
        ).trimmed
        let appBinary = "\(appBinDir)/\(context.productName)"
        guard FileManager.default.isExecutableFile(atPath: appBinary) else {
            throw SetupCommand.Error.invalidValue("app binary", "expected binary was not produced at '\(appBinary)'")
        }

        try await UserShell.runAsServiceUser(context, ["install", "-d", "-m", "0755", paths.appDeployDirectory], environment: env)
        try await UserShell.runAsServiceUser(
            context,
            ["install", "-m", "0755", appBinary, "\(paths.appDeployDirectory)/\(context.productName)"],
            environment: env
        )
        console.print("Build artifacts installed.")
    }

}
