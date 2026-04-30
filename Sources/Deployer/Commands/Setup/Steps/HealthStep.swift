import Vapor

/// Verifies that both the deployer and the target app services have successfully started and are accepting local connections.
struct HealthStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Running health checks"

    func run() async throws {
        
        try await waitForService("deployer")
        console.print("Deployer service is running.")

        try await waitForService(context.productName)
        console.print("App service is running.")

        try await waitForTCP(port: context.deployerPort)
        console.print("Deployer listening on 127.0.0.1:\(context.deployerPort).")

        try await waitForTCP(port: context.appPort)
        console.print("App listening on 127.0.0.1:\(context.appPort).")

        try verifyAppBinary()
    }

}

extension HealthStep {

    private func waitForService(_ service: String) async throws {

        for _ in 0..<30 {
            if await isServiceRunning(service) { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw SystemError.serviceTimeout(service)
    }

    private func waitForTCP(port: Int) async throws {

        for _ in 0..<30 {
            let result = await Shell.run("exec 3<>/dev/tcp/127.0.0.1/\(port)")
            if result.exitCode == 0 { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw SystemError.serviceTimeout("127.0.0.1:\(port)")
    }

    private func verifyAppBinary() throws {

        if !FileManager.default.isExecutableFile(atPath: "\(paths.appDeployDirectory)/\(context.productName)") {
            throw SystemError.invalidValue("app binary", "missing deployed app binary")
        }
    }

}

extension HealthStep {

    private func isServiceRunning(_ service: String) async -> Bool {
        let configurator = context.serviceManagerKind.makeConfigurator(shell: shell, paths: paths)
        return await configurator.isRunning(service)
    }

}
