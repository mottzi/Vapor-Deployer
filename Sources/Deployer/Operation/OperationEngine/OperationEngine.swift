import Vapor

/// Shared executor for mutating deployment operations across the panel, coordinator, and CLI.
struct OperationEngine: Sendable {

    let app: Application
    let config: Configuration
    let origin: Operation.Origin
    let onStatusChange: @Sendable (ServiceStatus) async -> Void

    init(
        app: Application,
        config: Configuration,
        origin: Operation.Origin = .server,
        onStatusChange: @escaping @Sendable (ServiceStatus) async -> Void = { _ in }
    ) {
        self.app = app
        self.config = config
        self.origin = origin
        self.onStatusChange = onStatusChange
    }

}

extension OperationEngine {

    /// The specific user-initiated deployment, compilation, or target cleanup command.
    enum Action: Sendable {
        
        case deploy
        case automaticDeploy
        case build
        case runSavedBinary
        case test
        case delete
        case removeBinary

        var kind: Operation.Kind {
            switch self {
                case .deploy, .automaticDeploy: .deploy
                case .build: .build
                case .runSavedBinary: .run
                case .test: .test
                case .delete: .delete
                case .removeBinary: .removeBinary
            }
        }
        
    }

    /// Rules determining whether target-specific test suites must be executed during operation pipelines.
    enum TestPolicy: Sendable {
        case configured
        case forceEnabled
        case forceDisabled
    }

    /// Configuration settings tailoring test execution behavior and output routing for an engine run.
    struct Options: Sendable {
        var testPolicy: TestPolicy = .configured
        var consoleSink: OperationOutputConsoleSink?
    }

}

extension OperationEngine {

    /// Runs one operation while the caller retains the cross-process operation lock.
    func run(action: Action, deployment: Deployment, options: Options = Options()) async throws {

        let session = try await OperationSession.begin(
            app: app,
            kind: action.kind,
            origin: origin,
            product: config.target.name,
            deploymentID: deployment.id
        )
        
        let recorder = session.recorder
        
        do {
            switch action {
                case .deploy: try await runPromote(deployment: deployment, options: options, recorder: recorder)
                case .automaticDeploy: try await runAutomaticQueue(startingWith: deployment, options: options, recorder: recorder)
                case .build: try await runBuild(deployment: deployment, options: options, recorder: recorder)
                case .runSavedBinary: try await runSavedBinary(deployment: deployment, options: options, recorder: recorder)
                case .test: try await runTest(deployment: deployment, options: options, recorder: recorder)
                case .delete: try await runDelete(deployment: deployment, recorder: recorder)
                case .removeBinary: try await runRemoveBinary(deployment: deployment, recorder: recorder)
            }
            await session.complete(deploymentID: deployment.id)
            await session.cleanupIfServerOrigin()
        } catch {
            await session.fail(deploymentID: deployment.id)
            await session.cleanupIfServerOrigin()
            throw error
        }
    }

}
