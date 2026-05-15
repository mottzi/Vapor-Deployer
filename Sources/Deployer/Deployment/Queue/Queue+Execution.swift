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
            await drainQueue(startingWith: initialDeployment)
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
            do {
                await stream.start()
                try await worker.checkout(streamingTo: stream)
                await stream.appendLabel("swift build -c \(target.buildMode)")
                try await worker.build(streamingTo: stream)
                await stream.appendLabel("archive binary")
                try await store.storeBuiltBinary(for: deployment, app: app, manually: true)
                await stream.flush()
                deployment.status = .built
                deployment.finishedAt = .now
                deployment.output = await stream.transcript
                await stream.close()
                try await deployment.save(on: app.db)
            } catch {
                await fail(deployment: deployment, stream: stream, error: error)
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
                await failWithoutStream(deployment: deployment, error: error)
            }

        case .deploy:
            preconditionFailure("runSingle does not execute deploy jobs")
        }
    }

    /// Builds queued commits in sequence, promoting the most recent successful build to the live service.
    /// Honors a "last good build wins" policy: if a later iteration fails, the previous successful build is still promoted.
    func drainQueue(startingWith initialDeployment: Deployment) async {

        var current = initialDeployment
        var lastSuccessful: (deployment: Deployment, transcript: String)?

        while true {
            let worker = Worker(
                deployment: current,
                target: config.target,
                app: app,
                onStatusChange: onStatusChange
            )
            let stream = BuildOutputStream(app: app, deployment: current)

            do {
                await stream.start()
                try await worker.checkout(streamingTo: stream)
                await stream.appendLabel("swift build -c \(config.target.buildMode)")
                try await worker.build(streamingTo: stream)
                await stream.appendLabel("deployer")
                try await worker.move()
                await stream.append("Install binary.\n")
                await stream.flush()
            } catch {
                await fail(deployment: current, stream: stream, error: error)
                if let last = lastSuccessful {
                    await finalize(deployment: last.deployment, priorTranscript: last.transcript)
                }
                return
            }

            guard let next = try? await findNextDeployment(after: current) else {
                await finalize(deployment: current, stream: stream)
                return
            }

            current.status = .built
            current.finishedAt = .now
            current.output = await stream.transcript
            try? await current.save(on: app.db)

            let transcript = await stream.transcript
            await stream.close()

            next.status = .building
            try? await next.save(on: app.db)

            lastSuccessful = (current, transcript)
            current = next
        }
    }

    /// Restarts the service onto the just-built deployment, archives the binary, marks the row current, and evicts stale entries.
    /// Continues streaming step labels into the deployment log so the panel shows the entire pipeline live.
    func finalize(deployment: Deployment, stream: BuildOutputStream) async {
        let worker = Worker(
            deployment: deployment,
            target: config.target,
            app: app,
            onStatusChange: onStatusChange
        )
        let store = BinaryStore(target: config.target)

        do {
            try await worker.restart()
            await stream.append("Restart service.\n")
            try await store.storeLiveBinary(for: deployment, app: app, manually: false)
            await stream.append("Archive binary.\n")
            await stream.flush()

            deployment.finishedAt = .now
            deployment.output = await stream.transcript
            await stream.close()
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
        } catch {
            await fail(deployment: deployment, stream: stream, error: error)
        }
    }

    /// Finalizes a previously-successful build whose stream has already closed (last-good-build-wins path).
    /// On failure, the prior transcript is preserved and the error appended via `failWithoutStream`.
    func finalize(deployment: Deployment, priorTranscript: String) async {
        let worker = Worker(
            deployment: deployment,
            target: config.target,
            app: app,
            onStatusChange: onStatusChange
        )
        let store = BinaryStore(target: config.target)

        do {
            try await worker.restart()
            try await store.storeLiveBinary(for: deployment, app: app, manually: false)
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
        } catch {
            await failWithoutStream(deployment: deployment, priorTranscript: priorTranscript, error: error)
        }
    }

    /// Marks a deployment as failed, appends the error into the live stream, and persists the full transcript.
    func fail(deployment: Deployment, stream: BuildOutputStream, error: Swift.Error) async {
        await stream.appendError(error)
        await stream.flush()

        deployment.status = .failed
        deployment.finishedAt = .now
        deployment.output = await stream.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        await stream.close()
        try? await deployment.save(on: app.db)
    }

    /// Marks a deployment as failed when no live stream is attached (restore jobs and last-good-build-wins finalize).
    func failWithoutStream(deployment: Deployment, priorTranscript: String = "", error: Swift.Error) async {
        deployment.status = .failed
        deployment.finishedAt = .now

        let errorMessage = (error as? Shell.Error)?.output ?? error.localizedDescription
        let combined = priorTranscript.isEmpty
            ? errorMessage
            : priorTranscript + "\n\n" + errorMessage
        deployment.output = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        try? await deployment.save(on: app.db)
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

