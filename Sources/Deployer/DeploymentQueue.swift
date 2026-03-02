import Vapor

public actor DeploymentQueue
{
    var isDeploying: Bool = false
    
    let app: Application
    let config: DeployerConfiguration
    
    public init(app: Application, config: DeployerConfiguration)
    {
        self.app = app
        self.config = config
    }
    
    public func enqueue(message: String?, target: TargetConfiguration) async
    {
        let newDeployment = Deployment(
            productName: target.productName,
            status: !isDeploying ? .running : .canceled,
            message: message ?? ""
        )

        try? await newDeployment.save(on: app.db)

        guard !isDeploying else { return }
        isDeploying = true

        await drainQueue(startingWith: newDeployment, initialTarget: target)
    }
}

extension DeploymentQueue {
    
    func drainQueue(startingWith initialDeployment: Deployment, initialTarget: TargetConfiguration) async
    {
        var currentDeployment = initialDeployment
        var currentTarget = initialTarget
        
        while true
        {
            let executor = DeploymentWorker(target: currentTarget, app: app)
            
            do
            {
                if currentDeployment.mode == .standard
                {
                    try await executor.pull()
                    try await executor.build(currentDeployment)
                    try await executor.move(currentDeployment)
                }

                currentDeployment.status = .success
                currentDeployment.finishedAt = .now
                try await currentDeployment.save(on: app.db)
                
                guard let nextDeployment = try await findNextDeployment(after: currentDeployment) else
                {
                    try await currentDeployment.setCurrent(on: app.db)
                    try await executor.restart(currentDeployment)
                    break
                }
                
                try await handleTransition(from: currentDeployment, to: nextDeployment, worker: executor)
                
                nextDeployment.status = .running
                try? await nextDeployment.save(on: app.db)
                
                guard let nextTarget = config.target(for: nextDeployment.productName) else {
                    nextDeployment.status = .failed
                    nextDeployment.finishedAt = .now
                    nextDeployment.errorMessage = "Configuration missing for target: \(nextDeployment.productName)"
                    try? await nextDeployment.save(on: app.db)
                    Logger(label: "\(currentTarget.productName).Pipeline")
                        .error("Failed to find TargetConfiguration for '\(nextDeployment.productName)'")
                    break
                }

                currentTarget = nextTarget
                currentDeployment = nextDeployment
            }
            catch
            {
                currentDeployment.status = .failed
                currentDeployment.finishedAt = .now
                currentDeployment.errorMessage = error.localizedDescription
                try? await currentDeployment.save(on: app.db)
                Logger(label: "\(currentTarget.productName).Pipeline")
                    .error("\(error.localizedDescription)")
                break
            }
        }
        
        isDeploying = false
    }
    
    func findNextDeployment(after deployment: Deployment) async throws -> Deployment?
    {
        let cancelledDeployments = try await Deployment.query(on: app.db)
            .filter(\.$status, .equal, .canceled)
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
            if try await isSuperseded(sameProduct) == false
            {
                return sameProduct
            }
        }
        
        let differentProductCandidates = cancelledDeploymentByProduct.values
            .filter { $0.productName != config.deployer.productName && $0.productName != deployment.productName }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        
        for candidate in differentProductCandidates
        {
            if try await isSuperseded(candidate) == false
            {
                return candidate
            }
        }
        
        if let deployerProduct = cancelledDeploymentByProduct[config.deployer.productName]
        {
            if try await isSuperseded(deployerProduct) == false
            {
                return deployerProduct
            }
        }
        
        return nil
    }
    
    func isSuperseded(_ deployment: Deployment) async throws -> Bool
    {
        guard let startedAt = deployment.startedAt else { return false }
        
        if let currentDeployment = try await Deployment.getCurrent(named: deployment.productName, on: app.db),
           let currentStartedAt = currentDeployment.startedAt,
           currentStartedAt >= startedAt
        {
            return true
        }

        let isSuperseded = try await Deployment.query(on: app.db)
            .filter(\.$productName, .equal, deployment.productName)
            .filter(\.$startedAt, .greaterThan, startedAt)
            .group(.or)
            {
                $0
                    .filter(\.$status, .equal, .success)
                    .filter(\.$status, .equal, .deployed)
            }
            .first() != nil

        return isSuperseded
    }
    
    func handleTransition(from deployment: Deployment, to nextDeployment: Deployment, worker: DeploymentWorker) async throws
    {
        let isDeployer = deployment.productName == config.deployer.productName
        let isSameProduct = deployment.productName == nextDeployment.productName
        
        if isDeployer && !isSameProduct
        {
            let hasPendingDeployerRestart = try await Deployment.query(on: app.db)
                .filter(\.$productName, .equal, config.deployer.productName)
                .filter(\.$status, .equal, .canceled)
                .filter(\.$mode, .equal, Deployment.Mode.restartOnly)
                .first() != nil

            if hasPendingDeployerRestart == false
            {
                let deferredDeployment = Deployment(
                    productName: deployment.productName,
                    status: .canceled,
                    message: deployment.message,
                    mode: .restartOnly
                )
                
                try await deferredDeployment.save(on: app.db)
            }
        }
        else if !isSameProduct
        {
            try await deployment.setCurrent(on: app.db)
            try await worker.restart(deployment)
        }
    }
}
