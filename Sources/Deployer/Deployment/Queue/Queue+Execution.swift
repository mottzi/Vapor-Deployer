import Vapor

extension Queue {

    /// Determines which execution path the queue takes for a given job.
    enum JobMode: Sendable {
        /// Full build-and-deploy pipeline, draining any queued pushes in sequence.
        case deploy
        /// Build and archive the binary without deploying it live.
        case saveBinary
        /// Swap the live binary from a previously saved archive.
        case restoreBinary
    }

    /// Outcome returned to callers after attempting to start a queue job.
    enum StartResult: Sendable {
        /// Job accepted and running in the background.
        case started
        /// Rejected because another job is already in progress.
        case queueBusy
        /// Job could not start due to a DB or internal error.
        case failure(String)
    }

}

extension Queue {

    /// Broadcasts current queue state to connected live panel clients.
    func updateUI() async {
        let newState = QueueState(isDeploying: isDeploying)
        await queueState.set(newState)
    }

    /// Dispatches to drainQueue or runSingle based on mode, then resets isDeploying on completion.
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

    /// Executes a saveBinary or restoreBinary job to completion.
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

    /// Builds and deploys queued commits in sequence until none remain.
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

    /// Marks a deployment as failed, assembles final output from build log and error, and persists to DB.
    func fail(deployment: Deployment, stream: BuildOutputStream?, capturedOutput: String?, error: Swift.Error) async {
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

}

extension Queue {

    /// Returns the most recent canceled deployment queued after the given one, or nil if none exists or all are superseded.
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

    /// Returns true if a newer successful deployment has already run, making this candidate stale.
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

