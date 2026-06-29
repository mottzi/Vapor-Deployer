import Vapor
import Fluent

/// Resolves operator-provided Git SHAs to deployment rows.
enum DeploymentSelector {

    /// Resolves a known deployment row, optionally creating a row for a reachable commit on the configured branch.
    static func resolve(
        _ selector: String,
        config: Configuration,
        app: Application,
        allowCreate: Bool
    ) async throws -> Deployment {

        let known = try await Deployment.query(on: app.db)
            .filter(\.$product, .equal, config.target.name)
            .all()
            .filter { $0.commitID.hasPrefix(selector) }

        if known.count == 1 { return known[0] }
        if known.count > 1 { throw OperationError.ambiguousSHA(selector, known) }
        guard allowCreate else { throw OperationError.deploymentNotFound(selector) }

        return try await createReachableDeployment(selector, config: config, app: app)
    }

    /// Resolves a known deployment row without creating a missing row.
    static func resolveExisting(_ selector: String, config: Configuration, app: Application) async throws -> Deployment {
        try await resolve(selector, config: config, app: app, allowCreate: false)
    }

}

private extension DeploymentSelector {

    /// Creates a pushed deployment row for a commit reachable from the configured branch.
    static func createReachableDeployment(_ selector: String, config: Configuration, app: Application) async throws -> Deployment {

        let target = config.target

        do {
            try await Shell.runThrowing("git", ["fetch", "origin", target.branch], directory: target.directory)
        } catch {
            throw OperationError.unreachableSHA(selector)
        }

        let resolved: String
        do {
            resolved = try await Shell.runThrowing(
                "git",
                ["rev-parse", "--verify", "\(selector)^{commit}"],
                directory: target.directory
            ).trimmed
        } catch {
            throw OperationError.unreachableSHA(selector)
        }

        let reachable = await Shell.run(
            "git",
            ["merge-base", "--is-ancestor", resolved, "origin/\(target.branch)"],
            directory: target.directory
        )
        guard reachable.exitCode == 0 else { throw OperationError.unreachableSHA(selector) }

        let message = (try? await Shell.runThrowing(
            "git",
            ["log", "-1", "--format=%s", resolved],
            directory: target.directory
        ).trimmed) ?? resolved

        let deployment = Deployment(
            product: target.name,
            status: .pushed,
            commitMessage: message,
            commitID: resolved,
            branch: target.branch
        )
        try await deployment.save(on: app.db)
        return deployment
    }

}
