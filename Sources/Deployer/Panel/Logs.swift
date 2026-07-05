import Vapor

extension Panel {

    func serveTargetAppLogs(request: Request) async throws -> View {

        let targetAppLogs = await request.application.mistComponent(TargetAppLogs.self) ?? TargetAppLogs()
        let targetAppLogsHTML = await targetAppLogs.renderInitial(app: request.application) ?? ""

        let context = LogsContext(
            deployer: LogsContext.Deployer(
                panelRoute: panelPath,
                repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
            ),
            title: "Target App Logs",
            source: LogsContext.Source(
                label: "Target",
                name: config.target.name,
                logFilePath: config.target.logFilePath.displayPath
            ),
            componentName: TargetAppLogs.componentName,
            streamName: TargetAppLogs.streamName,
            retainedLineCount: TargetAppLogs.retainedLineCount,
            consoleID: "dp-app-log-console",
            logsHTML: targetAppLogsHTML
        )

        return try await request.view.render("Deployer/DeployerLogs", context)
    }

    func serveDeployerLogs(request: Request) async throws -> View {

        let deployerLogs = await request.application.mistComponent(DeployerLogs.self) ?? DeployerLogs()
        let deployerLogsHTML = await deployerLogs.renderInitial(app: request.application) ?? ""

        let context = LogsContext(
            deployer: LogsContext.Deployer(
                panelRoute: panelPath,
                repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
            ),
            title: "Deployer Logs",
            source: LogsContext.Source(
                label: "Service",
                name: "Deployer",
                logFilePath: config.deployerLogFilePath.displayPath
            ),
            componentName: DeployerLogs.componentName,
            streamName: DeployerLogs.streamName,
            retainedLineCount: DeployerLogs.retainedLineCount,
            consoleID: "dp-deployer-log-console",
            logsHTML: deployerLogsHTML
        )

        return try await request.view.render("Deployer/DeployerLogs", context)
    }

}

extension Panel {

    struct LogsContext: Encodable {

        let deployer: Deployer
        let title: String
        let source: Source
        let componentName: String
        let streamName: String
        let retainedLineCount: Int
        let consoleID: String
        let logsHTML: String

        struct Deployer: Encodable {
            let panelRoute: String
            let repositoryWebPageURL: String
        }

        struct Source: Encodable {
            let label: String
            let name: String
            let logFilePath: String
        }

    }

}

