import Vapor

/// Verifies that the deployer control plane has successfully started and that the target app binary is installed.
struct HealthStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Checking control-plane health"

    func run() async throws {
        
        try await waitForService("deployer")
        console.print("Deployer service is running.")

        try await waitForTCP(port: context.deployerPort)
        console.print("Deployer listening on 127.0.0.1:\(context.deployerPort).")

        try verifyAppBinary()
    }

}

/// Checks the managed app as a workload state, surfacing failures without blocking control-plane installation.
struct ManagedAppHealthStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Checking managed app health"

    func run() async throws {

        var failures: [String] = []

        do {
            try await waitForService(context.productName)
            console.print("App service is running.")
        } catch {
            failures.append("App service '\(context.productName)': \(describe(error))")
        }

        if failures.isEmpty {
            do {
                try await waitForTCP(port: context.appPort)
                console.print("App listening on 127.0.0.1:\(context.appPort).")
            } catch {
                failures.append("App TCP 127.0.0.1:\(context.appPort): \(describe(error))")
            }
        } else {
            failures.append("App TCP 127.0.0.1:\(context.appPort): skipped because the app service is not running.")
        }

        context.managedAppHealthFailures = failures
        guard !failures.isEmpty else { return }

        console.warning("Managed app did not pass health checks. Setup will continue because the Deployer control plane is usable.")
        for failure in failures {
            console.warning(failure)
        }
    }

}

extension SetupStep {

    fileprivate func waitForService(_ service: String) async throws {

        for _ in 0..<30 {
            if await isServiceRunning(service) { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw Host.Error.serviceTimeout(service)
    }

    fileprivate func waitForTCP(port: Int) async throws {

        for _ in 0..<30 {
            let isListening = await Host.Network.canConnect(
                host: "127.0.0.1",
                port: port,
                timeout: .seconds(1),
                on: context.eventLoopGroup
            )
            if isListening { return }
            try await Task.sleep(for: .seconds(1))
        }

        throw Host.Error.serviceTimeout("127.0.0.1:\(port)")
    }

    fileprivate func describe(_ error: Swift.Error) -> String {
        if let described = error as? DescribedError {
            return described.description
        }

        return error.localizedDescription
    }

    fileprivate func isServiceRunning(_ service: String) async -> Bool {
        let configurator = context.serviceBackend.makeConfigurator(shell: shell, paths: paths)
        return await configurator.isRunning(service)
    }

}

extension HealthStep {

    private func verifyAppBinary() throws {

        if !FileManager.default.isExecutableFile(atPath: "\(paths.appDeployDirectory)/\(context.productName)") {
            throw Host.Error.invalidValue("app binary", "missing deployed app binary")
        }
    }

}
