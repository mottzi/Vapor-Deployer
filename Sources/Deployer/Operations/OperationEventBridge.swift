import Vapor
import Fluent
import Mist

extension Deployer {

    func useOperationEventBridge(
        config: Configuration,
        deployerPhase: LiveState<DeployerPhase>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        let bridge = OperationEventBridge(
            app: app,
            config: config,
            deployerPhase: deployerPhase,
            onStatusChange: onStatusChange
        )
        self.operationEventBridge = bridge
        Task { await bridge.start() }
    }

    var operationEventBridge: OperationEventBridge {
        get {
            if let bridge = app.storage[OperationEventBridgeKey.self] { return bridge }
            fatalError("Operation event bridge not initialized.")
        }
        nonmutating set {
            app.storage[OperationEventBridgeKey.self] = newValue
        }
    }

    private struct OperationEventBridgeKey: StorageKey { typealias Value = OperationEventBridge }

}

/// Mirrors durable operation events into the online Mist runtime.
actor OperationEventBridge {

    static let pollInterval: Duration = .milliseconds(250)

    let app: Application
    let config: Configuration
    let deployerPhase: LiveState<DeployerPhase>
    let onStatusChange: @Sendable (ServiceStatus) async -> Void

    private var lastSequences: [UUID: Int] = [:]
    private var terminalObserved: Set<UUID> = []

    init(
        app: Application,
        config: Configuration,
        deployerPhase: LiveState<DeployerPhase>,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void
    ) {
        self.app = app
        self.config = config
        self.deployerPhase = deployerPhase
        self.onStatusChange = onStatusChange
    }

    /// Polls operation events for the lifetime of the server process.
    func start() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func tick() async {
        do {
            let operations = try await Operation.query(on: app.db)
                .filter(\.$product, .equal, config.target.name)
                .filter(\.$origin, .equal, .cli)
                .group(.or) {
                    $0
                        .filter(\.$status, .equal, .running)
                        .filter(\.$status, .equal, .completed)
                        .filter(\.$status, .equal, .failed)
                }
                .sort(\.$createdAt, .ascending)
                .all()

            for operation in operations {
                try await consume(operation)
            }

            await updatePhase()
        } catch {
            app.logger.error("Operation event bridge failed: \(error.localizedDescription)")
        }
    }

    /// Applies new events for one operation in sequence order.
    private func consume(_ operation: Operation) async throws {

        guard let operationID = operation.id else { return }
        let lastSequence = lastSequences[operationID] ?? 0

        let events = try await OperationEvent.query(on: app.db)
            .filter(\.$operationID, .equal, operationID)
            .filter(\.$sequence, .greaterThan, lastSequence)
            .sort(\.$sequence, .ascending)
            .all()

        guard !events.isEmpty else {
            if operation.status != .running && terminalObserved.contains(operationID) {
                await OperationRecovery.cleanupTerminalOperation(operation, on: app.db)
                lastSequences[operationID] = nil
                terminalObserved.remove(operationID)
            }
            return
        }

        let sawTerminalEvent = events.contains(where: { $0.type == .completed || $0.type == .failed })
        for event in events {
            await apply(event)
            lastSequences[operationID] = event.sequence
        }

        if sawTerminalEvent {
            terminalObserved.insert(operationID)
        }

        if operation.status != .running && terminalObserved.contains(operationID) {
            await OperationRecovery.cleanupTerminalOperation(operation, on: app.db)
            lastSequences[operationID] = nil
            terminalObserved.remove(operationID)
        }
    }

    /// Applies one operation event to Mist streams, row rendering, or target status state.
    private func apply(_ event: OperationEvent) async {

        switch event.type {
        case .started:
            guard let deploymentID = event.deploymentID else { return }
            await app.mist.streams.replace(
                component: DeploymentRow.name(for: config.target.name),
                modelID: deploymentID,
                stream: DeploymentOutput.streamName,
                text: event.payload ?? ""
            )

        case .logAppended:
            guard let deploymentID = event.deploymentID else { return }
            await app.mist.streams.append(
                component: DeploymentRow.name(for: config.target.name),
                modelID: deploymentID,
                stream: DeploymentOutput.streamName,
                text: event.payload ?? ""
            )

        case .rowUpdated:
            await refreshRow(id: event.deploymentID)

        case .rowDeleted:
            await deleteRow(id: event.deploymentID)

        case .serviceStatus:
            if let payload = event.payload, let status = ServiceStatus(rawValue: payload) {
                await onStatusChange(status)
            }

        case .completed, .failed:
            if let deploymentID = event.deploymentID {
                await refreshRow(id: deploymentID)
                await app.mist.streams.close(
                    component: DeploymentRow.name(for: config.target.name),
                    modelID: deploymentID,
                    stream: DeploymentOutput.streamName
                )
            }
        }
    }

    /// Triggers Mist's model middleware from the server process for CLI-origin row updates.
    private func refreshRow(id: UUID?) async {
        guard let id else { return }

        do {
            guard let deployment = try await Deployment.find(id, on: app.db) else { return }
            try await deployment.save(on: app.db)
        } catch {
            app.logger.error("Failed to refresh deployment row \(id): \(error.localizedDescription)")
        }
    }

    /// Emits a server-process model deletion event for rows deleted by an offline-capable CLI process.
    private func deleteRow(id: UUID?) async {
        guard let id else { return }

        let tombstone = Deployment(
            product: config.target.name,
            status: .pushed,
            commitMessage: "",
            commitID: "",
            branch: config.target.branch
        )
        tombstone.id = id

        do {
            try await tombstone.delete(on: app.db)
        } catch {
            app.logger.error("Failed to refresh deleted deployment row \(id): \(error.localizedDescription)")
        }
    }

    /// Keeps the runtime badge in sync with globally-held operation locks.
    private func updatePhase() async {
        guard let installDirectory = try? Configuration.getExecutableURL().deletingLastPathComponent() else { return }

        let phase: DeployerPhase
        if UpdateLock.isHeld(installDirectory: installDirectory) {
            phase = .updating
        } else if OperationLock.isHeld(installDirectory: installDirectory) {
            phase = .deploying
        } else {
            phase = await app.deployer.queue.isDeploying ? .deploying : .ready
        }

        await deployerPhase.set(phase)
    }

}
