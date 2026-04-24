import Vapor

struct PreflightStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preflight checks"

    func run() async throws {
        
        if await UserAccount.exists(context.serviceUser) {
            try await verifyServiceUser()
            try await verifyDeployerCheckout()
            try await verifyAppCheckout()
        } else {
            console.print("Service user '\(context.serviceUser)' will be created")
        }

        console.print("Preflight checks passed.")
    }

}

extension PreflightStep {
    
    private func verifyServiceUser() async throws {
        
        let home = try await UserAccount.homeDirectory(for: context.serviceUser, errorLabel: "serviceUser")
        
        guard home == paths.serviceHome else {
            throw SystemError.invalidValue("serviceUser", "user exists with home '\(home)', not '\(paths.serviceHome)'")
        }
        
        console.print("Reusing user '\(context.serviceUser)' (home: \(home))")
    }
    
    private func verifyDeployerCheckout() async throws {
        
        let gitPath = "\(paths.installDirectory)/.git"
        
        if FileManager.default.fileExists(atPath: gitPath) {
            if context.buildFromSource {
                try await verifyGitCheckout(
                    at: paths.installDirectory,
                    expectedRemote: context.deployerRepositoryURL,
                    componentName: "deployer"
                )
            }
        } else if FileManager.default.fileExists(atPath: paths.installDirectory), context.buildFromSource {
            if try !isDirectoryEmpty(paths.installDirectory) {
                throw SystemError.invalidValue(
                    "installDirectory",
                    "'\(paths.installDirectory)' exists but is not an empty deployer checkout"
                )
            }
        }
    }
    
    private func verifyAppCheckout() async throws {
                
        if FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git") {
            try await verifyGitCheckout(
                at: paths.appDirectory,
                expectedRemote: context.appRepositoryURL,
                componentName: "app"
            )
        }
    }
    
}

extension PreflightStep {

    private func verifyGitCheckout(
        at path: String,
        expectedRemote: String,
        componentName: String
    ) async throws {
        
        let origin = try await shell.git("remote", ["get-url", "origin"], in: path).trimmed
        if !githubRemoteMatches(origin, expectedRemote) {
            throw SystemError.invalidValue("\(componentName) checkout", "existing origin '\(origin)' does not match '\(expectedRemote)'")
        }
        
        let dirty = try await shell.git("status", ["--porcelain", "--untracked-files=no"], in: path).trimmed
        if !dirty.isEmpty {
            throw SystemError.invalidValue("\(componentName) checkout", "existing checkout has uncommitted changes")
        }
    }
    
    private func isDirectoryEmpty(_ path: String) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: path).isEmpty
    }

    private func githubRemoteMatches(_ remoteA: String, _ remoteB: String) -> Bool {
        normalizeGithubRemote(remoteA) == normalizeGithubRemote(remoteB)
    }

    private func normalizeGithubRemote(_ remote: String) -> String {
            
        var url = remote.hasSuffix(".git")
            ? String(remote.dropLast(".git".count))
            : remote
        
        let prefixes = ["https://github.com/", "http://github.com/", "ssh://git@github.com/", "git@github.com:"]
        
        for prefix in prefixes where url.hasPrefix(prefix) {
            url = String(url.dropFirst(prefix.count))
            break
        }
        
        return url.lowercased()
    }
    
}
