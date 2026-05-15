import Vapor

extension Queue {
    
    /// Dispatches to drainQueue or runSingle based on mode, then resets isDeploying on completion.
    func run(mode: JobMode, startingWith deployment: Deployment, on target: TargetConfiguration) async {
        
        switch mode {
            case .deploy: await runQueue(startingWith: deployment)
            case .saveBinary: await runSaveBinary(on: deployment, target: target)
            case .restoreBinary: await runRestoreBinary(on: deployment, target: target)
        }
        
        isDeploying = false
        await broadcastState()
    }
    
    /// Checks out and builds the binary for the given deployment, then archives it without going live.
    func runSaveBinary(on deployment: Deployment, target: TargetConfiguration) async {
        let store = BinaryStore(target: target)
        let stream = BuildOutputStream(app: app, deployment: deployment)
        let worker = Worker(deployment: deployment, target: target, app: app, stream: stream, onStatusChange: onStatusChange)
        do {
            await stream.start()
            try await worker.checkout()
            try await worker.build()
            try await worker.save(to: store)
            await stream.flush()
            deployment.status = .built
            deployment.finishedAt = .now
            deployment.output = await stream.transcript
            await stream.close()
            try await deployment.save(on: app.db)
        } catch {
            await fail(deployment: deployment, stream: stream, error: error)
        }
    }

    /// Restores a previously archived binary and restarts the live service onto it.
    func runRestoreBinary(on deployment: Deployment, target: TargetConfiguration) async {
        
        let store = BinaryStore(target: target)
        let worker = Worker(deployment: deployment, target: target, app: app, stream: nil, onStatusChange: onStatusChange)
        
        do {
            try await worker.restore(from: store)
            try await worker.restart()
            deployment.finishedAt = .now
            
            try await store.syncMetadata(for: deployment, on: app.db)
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
        } catch {
            await fail(deployment: deployment, error: error)
        }
    }
    
    /// Builds queued commits in sequence, promoting the most recent successful build to the live service.
    /// Honors a "last good build wins" policy: if a later iteration fails, the previous successful build is still promoted.
    func runQueue(startingWith deployment: Deployment) async {
        
        var current = deployment
        var lastSuccessful: (deployment: Deployment, transcript: String)?
        
        while true {
            let stream = BuildOutputStream(app: app, deployment: current)
            let worker = Worker(deployment: current, target: config.target, app: app, stream: stream, onStatusChange: onStatusChange)
            
            do {
                await stream.start()
                try await worker.checkout()
                try await worker.build()
                try await worker.move()
                await stream.flush()
            } catch {
                await fail(deployment: current, stream: stream, error: error)
                if let last = lastSuccessful {
                    await finalizeQueue(deployment: last.deployment, priorTranscript: last.transcript)
                }
                return
            }
            
            guard let next = try? await nextQueuedDeployment(after: current) else {
                await finalizeQueue(deployment: current, stream: stream)
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
    
}

extension Queue {

    /// Restarts the service onto the just-built deployment, archives the binary, marks the row current, and evicts stale entries.
    func finalizeQueue(deployment: Deployment, stream: BuildOutputStream) async {
        
        let store = BinaryStore(target: config.target)
        let worker = Worker(deployment: deployment, target: config.target, app: app, stream: stream, onStatusChange: onStatusChange)

        do {
            try await worker.restart()
            try await worker.deploy(to: store)
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
    func finalizeQueue(deployment: Deployment, priorTranscript: String) async {
        
        let store = BinaryStore(target: config.target)
        let worker = Worker(deployment: deployment, target: config.target, app: app, stream: nil, onStatusChange: onStatusChange)

        do {
            try await worker.restart()
            try await worker.deploy(to: store)
            try await deployment.setCurrent(on: app.db)
            try await store.evict(on: app.db)
        } catch {
            await fail(deployment: deployment, transcript: priorTranscript, error: error)
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
    func fail(deployment: Deployment, transcript: String = "", error: Swift.Error) async {
        
        deployment.status = .failed
        deployment.finishedAt = .now

        let errorMessage = (error as? Shell.Error)?.output ?? error.localizedDescription
        let combined = transcript.isEmpty
            ? errorMessage
            : transcript + "\n\n" + errorMessage
        deployment.output = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        try? await deployment.save(on: app.db)
    }
    
    /// Broadcasts current queue state to connected live panel clients.
    func broadcastState() async {
        let newState = QueueState(isDeploying: isDeploying)
        await queueState.set(newState)
    }

}

extension Queue {

    /// Returns the most recent canceled deployment queued after the given one, or nil if none exists or all are superseded.
    func nextQueuedDeployment(after deployment: Deployment) async throws -> Deployment? {

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
