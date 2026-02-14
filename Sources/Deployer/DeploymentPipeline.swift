import Fluent
import Vapor

public struct PipelineConfiguration: Sendable
{
    let productName: String
    let workingDirectory: String
    let buildMode: String
    var pusheventPath: [PathComponent]
    
    public init(
        productName: String,
        workingDirectory: String,
        buildMode: String,
        pusheventPath: [PathComponent]
    ) {
        self.productName = productName
        self.workingDirectory = workingDirectory
        self.buildMode = buildMode
        self.pusheventPath = pusheventPath
    }
}

public struct DeploymentPipeline
{
    let app: Application
    
    let pipeline: PipelineConfiguration
    let deployer: DeployerConfiguration
    
    public func deploy(message: String? = nil) async
    {
        await start(message: message)
    }
    
    public init(
        pipeline: PipelineConfiguration,
        deployer: DeployerConfiguration,
        on app: Application
    ) {
        self.app = app
        self.pipeline = pipeline
        self.deployer = deployer
    }
}

extension DeploymentPipeline
{
    private func start(message: String?) async
    {
        let canDeploy = await Manager.shared.requestPipeline()

        let newDeployment = Deployment(
            productName: pipeline.productName,
            status: canDeploy ? "running" : "canceled",
            message: message ?? ""
        )

        try? await newDeployment.save(on: app.db)

        guard canDeploy else { return }

        do
        {
            try await run(newDeployment, on: app)
        }
        catch
        {
            await fail(newDeployment, with: error)
        }
    }
    
    private func resume(_ deployment: Deployment) async
    {
        guard await Manager.shared.requestPipeline() else { return }
        
        deployment.status = "running"
        try? await deployment.save(on: app.db)
        
        do
        {
            try await run(deployment, on: app)
        }
        catch
        {
            await fail(deployment, with: error)
        }
    }
    
    private func fail(_ deployment: Deployment, with error: Error) async
    {
        deployment.status = "failed"
        deployment.finishedAt = .now
        deployment.errorMessage = error.localizedDescription
        try? await deployment.save(on: app.db)
        await Manager.shared.endDeployment()
        Logger(label: "\(pipeline.productName).Pipeline").error("\(error.localizedDescription)")
    }
}

extension DeploymentPipeline
{
    private func run(_ deployment: Deployment, on app: Application) async throws
    {
        if deployment.mode == .standard
        {
            try await pull()
            try await build(deployment)
            try await move(deployment, using: app)
        }

        deployment.status = "success"
        deployment.finishedAt = .now
        try await deployment.save(on: app.db)
        await Manager.shared.endDeployment()
        
        guard let nextDeployment = try await findNextDeployment(after: deployment, on: app) else
        {
            try await deployment.setCurrent(on: app.db)
            try await restart(deployment)
            return
        }
        
        try await handleNextDeployment(nextDeployment, deployment: deployment, on: app)
    }
}

extension DeploymentPipeline
{
    private func findNextDeployment(after deployment: Deployment, on app: Application) async throws -> Deployment?
    {
        let cancelledDeployments = try await Deployment.query(on: app.db)
            .filter(\.$status, .equal, "canceled")
            .sort(\.$startedAt, .descending)
            .all()

        var cancelledDeploymentByProduct: [String: Deployment] = [:]
        for cancelledDeployment in cancelledDeployments
        {
            guard cancelledDeploymentByProduct[cancelledDeployment.productName] == nil else { continue }
            cancelledDeploymentByProduct[cancelledDeployment.productName] = cancelledDeployment
        }

        if let sameProduct = cancelledDeploymentByProduct[deployment.productName],
           let pendingTime = sameProduct.startedAt,
           let currentTime = deployment.startedAt,
           pendingTime > currentTime
        {
            if try await isSuperseded(sameProduct, on: app) == false
            {
                return sameProduct
            }
        }

        let differentProductCandidates = cancelledDeploymentByProduct.values
            .filter { $0.productName != deployer.deployer.productName && $0.productName != deployment.productName }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        
        for candidate in differentProductCandidates
        {
            if try await isSuperseded(candidate, on: app) == false
            {
                return candidate
            }
        }
        
        if let deployerProduct = cancelledDeploymentByProduct[deployer.deployer.productName]
        {
            if try await isSuperseded(deployerProduct, on: app) == false
            {
                return deployerProduct
            }
        }
        
        return nil
    }
    
    private func handleNextDeployment(_ nextDeployment: Deployment, deployment: Deployment, on app: Application) async throws
    {
        let isDeployer = deployment.productName == deployer.deployer.productName
        let isSameProduct = deployment.productName == nextDeployment.productName
        
        if isDeployer && !isSameProduct
        {
            let hasPendingDeployerRestart = try await Deployment.query(on: app.db)
                .filter(\.$productName, .equal, deployer.deployer.productName)
                .filter(\.$status, .equal, "canceled")
                .filter(\.$mode, .equal, Deployment.Mode.restartOnly)
                .first() != nil

            if hasPendingDeployerRestart == false
            {
                let deferredDeployment = Deployment(
                    productName: deployment.productName,
                    status: "canceled",
                    message: deployment.message,
                    mode: .restartOnly
                )
                
                try await deferredDeployment.save(on: app.db)
            }
            
            await resume(nextDeployment)
        }
        else if isSameProduct
        {
            await resume(nextDeployment)
        }
        else
        {
            try await deployment.setCurrent(on: app.db)
            try await restart(deployment)
            await resume(nextDeployment)
        }
    }

    private func isSuperseded(_ candidate: Deployment, on app: Application) async throws -> Bool
    {
        guard let candidateStartedAt = candidate.startedAt else { return false }
        
        if let current = try await Deployment.getCurrent(named: candidate.productName, on: app.db),
           let currentStartedAt = current.startedAt,
           currentStartedAt >= candidateStartedAt
        {
            return true
        }

        let exists = try await Deployment.query(on: app.db)
            .filter(\.$productName, .equal, candidate.productName)
            .filter(\.$startedAt, .greaterThan, candidateStartedAt)
            .group(.or) 
            {
                $0
                    .filter(\.$status, .equal, "success")
                    .filter(\.$status, .equal, "deployed")
            }
            .first() != nil

        return exists
    }
}

extension DeploymentPipeline
{
    private enum PipelineError: Error, LocalizedError
    {
        case initiateError(String)
        case executeError(String)
        case moveError(String)

        var errorDescription: String?
        {
            switch self
            {
                case .initiateError(let message): "Pipeline initiate error: \(message)"
                case .executeError(let message): "Pipeline execute error: \(message)"
                case .moveError(let message): "Pipeline move error: \(message)"
            }
        }
    }

    private func execute(_ command: String) async throws
    {
        try await withCheckedThrowingContinuation
        { (continuation: CheckedContinuation<Void, Error>) in

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: pipeline.workingDirectory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler =
            { [pipe, process] _ in

                guard process.terminationStatus != 0 else { return continuation.resume(returning: ()) }
                let output = String(
                    data: (try? pipe.fileHandleForReading.readToEnd()) ?? Data(),
                    encoding: .utf8)
                let error = PipelineError.executeError("Execution of '\(command)' failed with output:\n\n'\(output ?? "NO OUTPUT" )'")
                return continuation.resume(throwing: error)
            }

            do
            {
                try process.run()
            }
            catch
            {
                let error = PipelineError.initiateError("Start of '\(command)' failed with ourput:\n'\(error.localizedDescription)'")
                continuation.resume(throwing: error)
            }
        }
    }

    func pull() async throws
    {
        try await execute("git pull")
    }

    func build(_ deployment: Deployment) async throws
    {
        try await execute("swift build -c \(pipeline.buildMode)")
    }

    func restart(_ deployment: Deployment) async throws
    {
        try await execute("supervisorctl restart \(deployment.productName)")
    }

    func move(_ deployment: Deployment, using app: Application) async throws
    {
        let eventLoop = app.eventLoopGroup.any()
        let threadPool = app.threadPool

        let buildPath = "\(pipeline.workingDirectory)/.build/\(pipeline.buildMode)/\(deployment.productName)"
        let deployDir = "\(pipeline.workingDirectory)/deploy"
        let deployPath = "\(deployDir)/\(deployment.productName)"
        let backupPath = "\(deployDir)/\(deployment.productName).old"

        try await threadPool.runIfActive(eventLoop: eventLoop)
        {
            let fileManager = FileManager.default
            try fileManager.createDirectory(atPath: deployDir, withIntermediateDirectories: true)

            guard fileManager.fileExists(atPath: buildPath) else
            {
                throw PipelineError.moveError("New binary not found at \(buildPath)")
            }

            if fileManager.fileExists(atPath: backupPath) { try fileManager.removeItem(atPath: backupPath) }
            if fileManager.fileExists(atPath: deployPath) { try fileManager.moveItem(atPath: deployPath, toPath: backupPath) }

            do
            {
                try fileManager.moveItem(atPath: buildPath, toPath: deployPath)
                if fileManager.fileExists(atPath: backupPath) { try? fileManager.removeItem(atPath: backupPath) }
            }
            catch
            {
                let moveError = error

                if fileManager.fileExists(atPath: backupPath)
                {
                    do
                    {
                        if fileManager.fileExists(atPath: deployPath) { try fileManager.removeItem(atPath: deployPath) }
                        try fileManager.moveItem(atPath: backupPath, toPath: deployPath)
                    }
                    catch
                    {
                        let rollbackError = error

                        throw PipelineError.moveError(
                            """
                            Deployment failed: '\(moveError.localizedDescription)'.
                            Rollback failed: '\(rollbackError.localizedDescription)'.
                            """
                        )
                    }
                }

                throw PipelineError.moveError(
                    """
                    Deployment failed: '\(moveError.localizedDescription)'.
                    Rollback successfull.
                    """
                )
            }
        }.get()
    }
}

extension DeploymentPipeline
{
    actor Manager
    {
        static let shared = Manager()
        private init() {}

        private(set) var isDeploying: Bool = false

        func requestPipeline() -> Bool
        {
            guard isDeploying == false else { return false }
            isDeploying = true
            return true
        }

        func endDeployment()
        {
            isDeploying = false
        }
    }
}
