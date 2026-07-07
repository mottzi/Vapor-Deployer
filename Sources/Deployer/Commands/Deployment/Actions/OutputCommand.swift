import Vapor
import Fluent

/// Prints stored deployment output or follows live operation output to completion.
struct OutputCommand: AnyAsyncCommand {

    var help: String { "Show deployment output." }

    /// Attaches to the active operation event stream if running, otherwise prints the final output transcript.
    func run(using context: inout CommandContext) async throws {

        let args = context.input.arguments
        context.input.arguments = []

        let parsed = try DeploymentCLI.parse(args)
        try DeploymentCLI.validateFlags(parsed, allowed: [])
        guard parsed.positionals.count == 1 else {
            throw DeploymentCLI.Error.usage("Usage: deployerctl output <sha>")
        }

        let (config, _) = try await DeploymentCLI.runtime(from: context)
        let deployment = try await DeploymentSelector.resolveExisting(parsed.positionals[0], config: config, app: context.application)

        if let operation = try await activeOperation(for: deployment, product: config.target.name, app: context.application) {
            try await follow(operation: operation, deploymentID: deployment.id, console: context.console, app: context.application)
            return
        }

        if let output = deployment.output, !output.isEmpty {
            context.console.output(output.consoleText())
        }
    }

}

extension OutputCommand {

    /// Finds an active operation for the selected deployment.
    private func activeOperation(for deployment: Deployment, product: String, app: Application) async throws -> Operation? {
        guard let deploymentID = deployment.id else { return nil }

        return try await Operation.query(on: app.db)
            .filter(\.$product, .equal, product)
            .filter(\.$origin, .equal, .cli)
            .filter(\.$deploymentID, .equal, deploymentID)
            .filter(\.$status, .equal, .running)
            .sort(\.$createdAt, .descending)
            .first()
    }

    /// Follows operation events until a terminal event is observed.
    private func follow(operation: Operation, deploymentID: UUID?, console: any Console, app: Application) async throws {
        guard let operationID = operation.id else { return }

        var lastSequence = 0
        var isComplete = false
        var printed = ""

        while !isComplete {
            let events = try await OperationEvent.query(on: app.db)
                .filter(\.$operationID, .equal, operationID)
                .filter(\.$sequence, .greaterThan, lastSequence)
                .sort(\.$sequence, .ascending)
                .all()

            for event in events {
                lastSequence = event.sequence
                switch event.type {
                case .outputOpened:
                    if let payload = event.payload, !payload.isEmpty {
                        printed.append(payload)
                        console.output(payload.consoleText(), newLine: false)
                    }
                case .logAppended:
                    if let payload = event.payload {
                        printed.append(payload)
                        console.output(payload.consoleText(), newLine: false)
                    }
                case .completed, .failed:
                    isComplete = true
                case .rowUpdated, .rowDeleted, .serviceStatus:
                    break
                }
            }

            if !isComplete {
                if let current = try await Operation.find(operationID, on: app.db) {
                    isComplete = current.status != .running
                } else {
                    isComplete = true
                }
            }

            if !isComplete {
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        try await printFinalOutputSuffix(deploymentID: deploymentID, printed: printed, console: console, app: app)
    }

    /// Prints any persisted transcript tail that may have been cleaned from operation events before this follower observed it.
    private func printFinalOutputSuffix(deploymentID: UUID?, printed: String, console: any Console, app: Application) async throws {
        guard let deploymentID else { return }
        guard let deployment = try await Deployment.find(deploymentID, on: app.db) else { return }
        guard let output = deployment.output, output.hasPrefix(printed), output.count > printed.count else { return }

        let suffix = output.dropFirst(printed.count)
        console.output(String(suffix).consoleText(), newLine: false)
    }

}
