import Vapor

extension Queue {

    enum JobMode: Sendable {
        case deploy
        case saveBinary
        case restoreBinary
    }

    enum StartResult: Sendable {
        case started
        case queueBusy
        case failure(String)
    }

    func updateUI() async {
        let newState = QueueState(isDeploying: isDeploying)
        await queueState.set(newState)
    }

    func run(mode: JobMode, startingWith initialDeployment: Deployment, initialTarget: TargetConfiguration) async {
        switch mode {
        case .deploy:
            await drainQueue(startingWith: initialDeployment, initialTarget: initialTarget)
        case .saveBinary, .restoreBinary:
            await runSingle(deployment: initialDeployment, target: initialTarget, mode: mode)
        }

        isDeploying = false
        await updateUI()
    }

    func runSingle(deployment: Deployment, target: TargetConfiguration, mode: JobMode) async {
        let worker = Worker(
            deployment: deployment,
            target: target,
            app: app,
            onStatusChange: onStatusChange
        )
        let store = BinaryStore(target: target)

        switch mode {
        case .saveBinary:
            let stream = BuildOutputStream(app: app, deployment: deployment)
            var capturedOutput: String?
            do {
                await stream.start()
                try await worker.checkout()
                capturedOutput = try await worker.build(streamingTo: stream)
                await stream.flush()
                try await store.storeBuiltBinary(for: deployment, app: app, manually: true)
                deployment.status = .built
                deployment.finishedAt = .now
                deployment.output = capturedOutput
                try await deployment.save(on: app.db)
                await stream.close()
            } catch {
                await fail(deployment: deployment, stream: stream, capturedOutput: capturedOutput, error: error)
            }

        case .restoreBinary:
            do {
                try await worker.restore(from: store)
                try await worker.restart()
                deployment.finishedAt = .now
                try await store.syncMetadata(for: deployment, on: app.db)
                try await deployment.setCurrent(on: app.db)
                try await store.evict(on: app.db)
            } catch {
                await fail(deployment: deployment, stream: nil, capturedOutput: nil, error: error)
            }

        case .deploy:
            preconditionFailure("runSingle does not execute deploy jobs")
        }
    }

    func drainQueue(startingWith initialDeployment: Deployment, initialTarget: TargetConfiguration) async {

        var currentDeployment = initialDeployment
        var currentTarget = initialTarget

        while true {
            let worker = Worker(
                deployment: currentDeployment,
                target: currentTarget,
                app: app,
                onStatusChange: onStatusChange
            )
            let stream = BuildOutputStream(app: app, deployment: currentDeployment)

            var capturedOutput: String?
            do {
                await stream.start()
                try await worker.checkout()
                capturedOutput = try await worker.build(streamingTo: stream)
                await stream.flush()
                try await worker.move()

                currentDeployment.status = .built
                currentDeployment.finishedAt = .now
                currentDeployment.output = capturedOutput
                try await currentDeployment.save(on: app.db)

                guard let nextDeployment = try await findNextDeployment(after: currentDeployment) else {
                    try await worker.restart()
                    let store = BinaryStore(target: currentTarget)
                    try await store.storeLiveBinary(for: currentDeployment, app: app, manually: false)
                    try await currentDeployment.setCurrent(on: app.db)
                    try await store.evict(on: app.db)
                    await stream.close()
                    break
                }

                await stream.close()

                nextDeployment.status = .building
                try? await nextDeployment.save(on: app.db)

                currentTarget = config.target
                currentDeployment = nextDeployment
            } catch {
                await fail(deployment: currentDeployment, stream: stream, capturedOutput: capturedOutput, error: error)
                break
            }
        }
    }

    func fail(
        deployment: Deployment,
        stream: BuildOutputStream?,
        capturedOutput: String?,
        error: Swift.Error
    ) async {
        if let stream { await stream.flush() }
        deployment.status = .failed
        deployment.finishedAt = .now

        var finalOutput = ""
        if let capturedOutput {
            finalOutput = capturedOutput + "\n\n"
        }

        if let shellError = error as? Shell.Error {
            finalOutput += shellError.output
        } else {
            finalOutput += error.localizedDescription
        }
        deployment.output = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        try? await deployment.save(on: app.db)
        if let stream { await stream.close() }
    }

    func findNextDeployment(after deployment: Deployment) async throws -> Deployment? {

        guard let currentTime = deployment.startedAt else { return nil }

        let candidate = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, deployment.product)
            .filter(\.$status, .equal, .canceled)
            .filter(\.$startedAt, .greaterThan, currentTime)
            .sort(\.$startedAt, .descending)
            .first()

        guard let candidate, try await !isSuperseded(candidate) else { return nil }
        return candidate
    }

    func isSuperseded(_ deployment: Deployment) async throws -> Bool {

        guard let startedAt = deployment.startedAt else { return false }

        if let currentDeployment = try await Deployment.getCurrent(named: deployment.product, on: app.db),
           let currentStartedAt = currentDeployment.startedAt,
           currentStartedAt >= startedAt {

            return true
        }

        let isSuperseded = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, deployment.product)
            .filter(\.$startedAt, .greaterThan, startedAt)
            .group(.or) {
                $0
                    .filter(\.$status, .equal, .built)
                    .filter(\.$status, .equal, .running)
            }
            .first() != nil

        return isSuperseded
    }

}
