import Vapor

extension Panel {

    func serveLogs(request: Request) async throws -> View {

        let context = LogsContext(
            deployer: LogsContext.Deployer(
                panelRoute: panelPath,
                repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
            ),
            target: LogsContext.Target(
                name: config.target.name,
                repositoryURL: config.target.repositoryURL,
                logFilePath: config.target.logFilePath.displayPath
            ),
            componentName: TargetAppLogs.componentName,
            streamName: TargetAppLogs.streamName,
            retainedLineCount: TargetAppLogs.retainedLineCount
        )

        return try await request.view.render("Deployer/DeployerLogs", context)
    }

}

extension Panel {

    struct LogsContext: Encodable {

        let deployer: Deployer
        let target: Target
        let componentName: String
        let streamName: String
        let retainedLineCount: Int

        struct Deployer: Encodable {
            let panelRoute: String
            let repositoryWebPageURL: String
        }

        struct Target: Encodable {
            let name: String
            let repositoryURL: String?
            let logFilePath: String
        }

    }

}
