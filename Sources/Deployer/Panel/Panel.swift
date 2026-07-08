import Vapor
import Fluent
import Mist

struct Panel {

    let config: Configuration
    let row: DeploymentRow
    let targetConfig: TargetConfig
    let deployerConfig: DeployerConfig
    let deployerStatus: DeployerStatus
    let panelPath: String
    let loginPath: String
    let authenticator: Authenticator

    init(
        config: Configuration,
        row: DeploymentRow,
        targetConfig: TargetConfig,
        deployerConfig: DeployerConfig,
        deployerStatus: DeployerStatus
    ) {
        self.panelPath = config.panelRoute.displayPath
        self.loginPath = panelPath == "/" ? "/login" : panelPath + "/login"
        self.authenticator = Authenticator(path: loginPath)
        self.config = config
        self.row = row
        self.targetConfig = targetConfig
        self.deployerConfig = deployerConfig
        self.deployerStatus = deployerStatus
    }
    
    func servePanel(request: Request) async throws -> View {
        let context = try await makePanelContext(request: request)
        return try await request.view.render("Deployer/DeployerPanel", context)
    }

}

extension Panel {

    private func makePanelContext(request: Request) async throws -> PanelContext {

        try await BinaryStore(target: config.target).syncMetadata(product: config.target.name, on: request.db)

        async let rows = row.makeContext(ofAll: request.db)
        async let isRunning = request.application.deployer.serviceManager.isRunning(product: config.target.name)
        async let isDeploying = request.application.deployer.operations.isDeploying
        async let isUpdating = request.application.deployer.updater.isUpdating
        async let targetInfoRender = targetConfig.renderCurrent(app: request.application)
        async let deployerInfoRender = deployerConfig.renderCurrent(app: request.application)

        let resolvedState = await DeployerPhase.resolve(
            updaterIsUpdating: isUpdating,
            operationIsDeploying: isDeploying
        )
        await deployerStatus.state.set(resolvedState)
        async let deployerStateRender = deployerStatus.renderCurrent(app: request.application)

        let deployer = DeployerContext(
            panelRoute: config.panelRoute.displayPath,
            repositoryWebPageURL: DeployerVersion.repositoryWebPageURL,
            infoComponentName: deployerConfig.name,
            infoInitialHTML: await deployerInfoRender.html ?? "",
            stateComponentName: deployerStatus.name,
            stateInitialHTML: await deployerStateRender.html ?? "",
            state: resolvedState.rawValue
        )

        let target = TargetContext(
            name: config.target.name,
            repositoryURL: config.target.repositoryURL,
            directory: config.target.directory,
            buildMode: config.target.buildMode,
            deployMode: config.target.deploymentMode.rawValue,
            pushEvent: config.target.pusheventPath.displayPath,
            rows: try await rows.contexts,
            isRunning: await isRunning,
            targetConfigName: targetConfig.name,
            targetInfoInitialHTML: await targetInfoRender.html ?? ""
        )

        return PanelContext(deployer: deployer, target: target)
    }
    
}

extension Panel {
    
    private struct PanelContext: Encodable {
        let deployer: DeployerContext
        let target: TargetContext
    }

    private struct DeployerContext: Encodable {
        let panelRoute: String
        let repositoryWebPageURL: String
        let infoComponentName: String
        let infoInitialHTML: String
        let stateComponentName: String
        let stateInitialHTML: String
        let state: String
    }

    private struct TargetContext: Encodable {
        let name: String
        let repositoryURL: String?
        let directory: String
        let buildMode: String
        let deployMode: String
        let pushEvent: String
        let rows: [ModelContext]
        let isRunning: Bool
        let targetConfigName: String
        let targetInfoInitialHTML: String
    }
    
}
