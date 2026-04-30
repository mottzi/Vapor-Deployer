import Vapor

/// Compiles the target app and optionally the deployer itself from source, and installs the resulting binaries.
struct BuildStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Building deployer and target app"

    func run() async throws {

        let configurator = context.serviceManagerKind.makeConfigurator(shell: shell, paths: paths)
        if await configurator.isRunning("deployer") {
            await configurator.disable(["deployer"])
        }

        if context.buildFromSource {
            try await buildDeployer()
        }
        
        try await buildTargetApp()
    }

}

extension BuildStep {

    private func buildDeployer() async throws {

        console.print("Building deployer in \(context.deployerBuildMode) mode...")
        
        try await shell.runAsServiceUserStreamingTail(
            swiftBinary, 
            ["build", "-c", context.deployerBuildMode], 
            directory: paths.installDirectory, 
            environment: buildEnvironment
        )
        
        let binDir = try await shell.runAsServiceUser(
            swiftBinary,
            ["build", "-c", context.deployerBuildMode, "--show-bin-path"],
            directory: paths.installDirectory,
            environment: buildEnvironment
        ).trimmed
        
        let binary = "\(binDir)/deployer"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw SystemError.invalidValue("deployer binary", "expected binary was not produced at '\(binary)'")
        }
        
        let tmpPath = SystemFileSystem.stagedInstallTmpPath(for: paths.deployerBinary)
        try await shell.runAsServiceUser(
            "install",
            ["-m", "0755", binary, tmpPath],
            environment: buildEnvironment
        )
        try await SystemFileSystem.commitStagedBinary(from: tmpPath, to: paths.deployerBinary)
    }

    private func buildTargetApp() async throws {

        console.print("Building target app in \(context.appBuildMode) mode...")
        
        try await shell.runAsServiceUserStreamingTail(
            swiftBinary, 
            ["build", "-c", context.appBuildMode], 
            directory: paths.appDirectory, 
            environment: buildEnvironment
        )
        
        let appBinDir = try await shell.runAsServiceUser(
            swiftBinary,
            ["build", "-c", context.appBuildMode, "--show-bin-path"],
            directory: paths.appDirectory,
            environment: buildEnvironment
        ).trimmed
        
        let appBinary = "\(appBinDir)/\(context.productName)"
        guard FileManager.default.isExecutableFile(atPath: appBinary) else {
            throw SystemError.invalidValue("app binary", "expected binary was not produced at '\(appBinary)'")
        }

        try await shell.runAsServiceUser(
            "install", 
            ["-d", "-m", "0755", paths.appDeployDirectory], 
            environment: buildEnvironment
        )
        
        let finalAppBinaryPath = "\(paths.appDeployDirectory)/\(context.productName)"
        let tmpAppPath = SystemFileSystem.stagedInstallTmpPath(for: finalAppBinaryPath)
        try await shell.runAsServiceUser(
            "install",
            ["-m", "0755", appBinary, tmpAppPath],
            environment: buildEnvironment
        )
        try await SystemFileSystem.commitStagedBinary(from: tmpAppPath, to: finalAppBinaryPath)
        
        console.print("Build artifacts installed.")
    }

}

extension BuildStep {

    private var swiftBinary: String {
        "\(paths.swiftlyBinDirectory)/swift"
    }

    private var buildEnvironment: [String: String] {
        ["HOME": paths.serviceHome, "USER": context.serviceUser, "PATH": paths.swiftPath]
    }

}
