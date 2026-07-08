import Mist
import Vapor

extension Deployer {
    
    func configureHTTP(config: Configuration) {
        app.http.server.configuration.port = config.port
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    }

    func configureViews() {
        app.views.use(.leaf)
    }

    func configureMist(config: Configuration) {
        app.mist.socket.path = config.socketPath.pathComponents
        app.mist.socket.middleware = app.sessions.middleware
        app.mist.socket.shouldUpgrade = { request in
            guard request.session.data["admin_auth"] == "true" else { return nil }
            return HTTPHeaders()
        }
    }

    func configurePanel(config: Configuration) async throws {
        let deploymentRow = DeploymentRow(productName: config.target.name)
        let targetConfig = TargetConfig(using: config)
        let deployerConfig = await DeployerConfig(
            using: config,
            version: DeployerVersion.current()
        )

        let deployerPhase = LiveState(of: DeployerPhase.resolve())
        useUpdater(config: config, deployerPhase: deployerPhase)
        let deployerStatus = DeployerStatus(state: deployerPhase, updater: updater)

        let initialStatus = await serviceManager.status(product: config.target.name)
        let badgeState = LiveState(of: StatusState(initialStatus))
        let actionsState = LiveState(of: StatusState(initialStatus))
        let broadcaster = TargetStatusBroadcaster(badge: badgeState, actions: actionsState)

        let targetStatus = TargetStatus(
            product: config.target.name,
            state: badgeState
        )
        let targetStatusActions = TargetStatusActions(
            product: config.target.name,
            state: actionsState,
            broadcaster: broadcaster
        )
        let targetAppLogs = TargetAppLogs()
        let targetAppLogTailer = FileLogTailer(app: app, logFilePath: config.target.logFilePath, logPrefix: "Target app")
        let targetAppLogStream = await app.mist.streams.staticStream(
            component: targetAppLogs.name,
            stream: TargetAppLogs.streamName,
            retainingLines: TargetAppLogs.retainedLineCount,
            onActive: {
                await targetAppLogTailer.start()
            },
            onInactive: {
                await targetAppLogTailer.stop()
            }
        )
        await targetAppLogTailer.configure(stream: targetAppLogStream)

        let deployerLogs = DeployerLogs()
        let deployerLogTailer = FileLogTailer(app: app, logFilePath: config.deployerLogFilePath, logPrefix: "Deployer")
        let deployerLogStream = await app.mist.streams.staticStream(
            component: deployerLogs.name,
            stream: DeployerLogs.streamName,
            retainingLines: DeployerLogs.retainedLineCount,
            onActive: {
                await deployerLogTailer.start()
            },
            onInactive: {
                await deployerLogTailer.stop()
            }
        )
        await deployerLogTailer.configure(stream: deployerLogStream)

        useOperations(
            config: config,
            deployerPhase: deployerPhase,
            onStatusChange: { status in
                await broadcaster.set(StatusState(status))
            }
        )
        useGitHubWebhook(config: config)
        usePanel(
            config: config,
            row: deploymentRow,
            targetConfig: targetConfig,
            deployerConfig: deployerConfig,
            deployerStatus: deployerStatus
        )

        try await app.mist.use {
            deploymentRow
            targetStatus
            targetStatusActions
            targetAppLogs
            deployerLogs
            deployerStatus
            targetConfig
            deployerConfig
        }
        startUpdaterPolling()

        useOperationEventBridge(
            config: config,
            deployerPhase: deployerPhase,
            onStatusChange: { status in
                await broadcaster.set(StatusState(status))
            }
        )

        await operations.drainOnBoot()
    }

}
