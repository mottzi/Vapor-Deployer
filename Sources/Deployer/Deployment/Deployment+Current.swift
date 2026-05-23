import Vapor
import Fluent

extension Deployment {

    func setCurrent(on database: Database) async throws {

        self.isLive = true
        self.status = .running
        try await self.save(on: database)

        guard let selfID = self.id else { throw Worker.Error.deploymentIDMissing }

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

}
