import Vapor
import Fluent

extension Deployment {

    func setCurrent(on database: Database) async throws {

        self.isLive = true
        self.status = .running
        try await self.save(on: database)

        guard let selfID = self.id else { throw OperationWorker.Error.deploymentIDMissing }

        let oldCurrentDeployments = try await Deployment.query(on: database)
            .filter(\.$isLive, .equal, true)
            .filter(\.$product, .equal, self.product)
            .filter(\.$id, .notEqual, selfID)
            .all()

        for deployment in oldCurrentDeployments {
            deployment.isLive = false
            deployment.status = .built
            try await deployment.save(on: database)
        }
    }

    static func getCurrent(named productName: String, on database: Database) async throws -> Deployment? {

        try await Deployment.query(on: database)
            .filter(\.$isLive, .equal, true)
            .filter(\.$product, .equal, productName)
            .first()
    }

    func isSuperseded(on database: Database) async throws -> Bool {

        guard let startedAt = self.startedAt else { return false }

        if let currentDeployment = try await Deployment.getCurrent(named: self.product, on: database),
           let currentStartedAt = currentDeployment.startedAt,
           currentStartedAt >= startedAt {

            return true
        }

        let isSuperseded = try await Deployment.query(on: database)
            .filter(\.$product, .equal, self.product)
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

