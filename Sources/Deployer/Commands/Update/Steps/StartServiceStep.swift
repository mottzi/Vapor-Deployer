import Vapor

/// Starts the updated service and verifies it runs stably.
struct StartServiceStep: UpdateStep {

    private static let controlHealthTimeout: TimeInterval = 10
    private static let controlHealthSettleDuration: TimeInterval = 3
    private static let controlHealthPollInterval: Duration = .milliseconds(500)

    let context: UpdateContext
    let console: any Console

    let title = "Starting service"

    func run() async throws {

        guard context.releaseVersion != context.currentVersion else { return }

        console.print("Starting service '\(context.serviceName)'.")
        
        let config = try Configuration.load()
        let manager = try config.serviceBackend.makeManager(serviceUser: context.managerServiceUser)
        
        try await manager.start(product: context.serviceName)

        let finalStatus = await manager.waitForStableStatus(product: context.serviceName)
        guard finalStatus.isRunning else { throw UpdateCommand.Error.restartVerificationFailed(finalStatus.label) }

        try await waitForControlHealth(config: config, manager: manager)
    }

    private func waitForControlHealth(config: Configuration, manager: any ServiceManager) async throws {

        let deadline = Date.now.addingTimeInterval(Self.controlHealthTimeout)
        var firstHealthyResponseAt: Date?
        var lastFailure = "control endpoint did not become healthy"

        while Date.now < deadline {
            let serviceStatus = await manager.status(product: context.serviceName)
            guard serviceStatus.isRunning else {
                throw UpdateCommand.Error.restartVerificationFailed("service crashed after start: \(serviceStatus.label)")
            }

            let outcome = await ControlPreflight.query(
                app: context.application,
                port: config.port,
                installDirectory: context.installDirectory
            )

            switch outcome {
                case .ready, .busy(_):
                    let now = Date.now
                    let healthySince = firstHealthyResponseAt ?? now
                    firstHealthyResponseAt = healthySince

                    if now.timeIntervalSince(healthySince) >= Self.controlHealthSettleDuration {
                        return
                    }

                case .unhealthy(let reason):
                    firstHealthyResponseAt = nil
                    lastFailure = "control endpoint unhealthy: \(reason)"

                case .unreachable(let reason):
                    firstHealthyResponseAt = nil
                    lastFailure = "control endpoint unreachable: \(reason)"
            }

            try await Task.sleep(for: Self.controlHealthPollInterval)
        }

        if firstHealthyResponseAt != nil {
            throw UpdateCommand.Error.restartVerificationFailed(
                "control endpoint did not remain healthy for \(Self.controlHealthSettleDuration)s"
            )
        }

        throw UpdateCommand.Error.restartVerificationFailed(lastFailure)
    }

}
