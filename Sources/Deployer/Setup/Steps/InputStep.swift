import Vapor
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct InputStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Collecting setup values"

    func run() async throws {
        
        collectRuntimeIdentity()
        collectTargetRepository()
        collectPortsAndRouting()
        collectServiceManager()
        try collectPanelAuthentication()
        try await collectPublicEndpoint()
        try await collectGitHubWebhookAccess()

        console.card(title: "Planned configuration", kvs: plannedConfiguration())
    }

}

extension InputStep {

    private func collectRuntimeIdentity() {
        
        console.section("Runtime identity")
        
        context.serviceUser = console.askValidated(
            "Dedicated service user",
            default: "vapor",
            warning: "Choose a non-root user containing only letters, numbers, dots, dashes, and underscores.",
            validate: SetupValidator.isNonRootSafeName
        )
    }

    private func collectTargetRepository() {
        
        console.section("Target repository")
        
        while true {
            let repoURL = console.askRequired("Private app repo SSH URL")
            if let parsed = SetupValidator.parseGitHubSSHURL(repoURL) {
                context.appRepositoryURL = repoURL
                context.githubOwner = parsed.owner
                context.githubRepo = parsed.repo
                break
            }
            console.warning("Use a GitHub SSH URL like git@github.com:owner/repo.git")
        }

        context.appName = console.askValidated(
            "Target app name",
            default: context.githubRepo,
            warning: "App name may contain only letters, numbers, dots, dashes, and underscores.",
            validate: SetupValidator.isSafeName
        )
    }

    private func collectPortsAndRouting() {
        
        console.section("Ports and routing")
        
        context.deployerPort = Int(console.askValidated(
            "Deployer port",
            default: "8081",
            warning: "Deployer port must be a number between 1 and 65535.",
            validate: SetupValidator.isValidPort
        )) ?? 8081

        context.appPort = Int(console.askValidated(
            "Target app port",
            default: "8080",
            warning: "Target app port must be a number between 1 and 65535.",
            validate: SetupValidator.isValidPort
        )) ?? 8080

        while true {
            var panelRoute = console.askRequired("Panel route", default: "/deployer")
            panelRoute = SetupValidator.normalizePanelRoute(panelRoute)
                
            guard panelRoute != "/" else {
                console.warning("Panel route '/' is not supported with managed Nginx setup. Use a prefixed route like /deployer.")
                continue
            }
            
            context.panelRoute = panelRoute
            break
        }
    }

    private func collectServiceManager() {
        
        console.section("Service manager")
        
        while true {
            let value = console.askRequired("Service manager", default: "systemd")
            guard let kind = ServiceManagerKind(rawValue: value) else {
                console.warning("Service manager must be 'systemd' or 'supervisor'.")
                continue
            }
            context.serviceManagerKind = kind
            break
        }

        context.buildFromSource = console.confirm("Build deployer from source?", defaultYes: false)
        context.paths = SetupPaths.derive(serviceUser: context.serviceUser, appName: context.appName, panelRoute: context.panelRoute)
    }

    private func collectPanelAuthentication() throws {
        console.section("Panel authentication")
        context.panelPassword = console.askSecretConfirmed("Panel password")
        context.webhookSecret = try generateHexSecret()
    }

    private func collectPublicEndpoint() async throws {
        
        console.section("Public endpoint")
        
        let publicURL = console.askValidated(
            "Public base URL",
            warning: "Public base URL must look like https://example.com (HTTPS + domain only, no path, no port).",
            validate: SetupValidator.isValidPublicBaseURL
        )
        
        context.publicBaseURL = SetupValidator.normalizeBaseURL(publicURL)
        context.primaryDomain = SetupValidator.extractHost(fromPublicBaseURL: publicURL)
        context.aliasDomain = SetupValidator.deriveAliasDomain(from: context.primaryDomain)
        context.certName = context.primaryDomain

        try await requireResolvableHostname(context.primaryDomain, label: "Canonical domain")
        try await requireResolvableHostname(context.aliasDomain, label: "Alias domain")

        context.tlsContactEmail = console.askValidated(
            "TLS contact email",
            warning: "TLS contact email must be a valid email address.",
            validate: SetupValidator.isValidEmail
        )
    }

    private func collectGitHubWebhookAccess() async throws {
        
        console.section("GitHub webhook access")
        
        console.card(
            title: "How to create the GitHub token",
            kvs: [
                ("Browser", "https://github.com/settings/tokens"),
                ("Click", "Generate new token > Generate new token (classic)"),
                ("Select", "admin:repo_hook")
            ]
        )
        
        try await collectAndVerifyGitHubToken()
    }

}

extension InputStep {
    
    private func generateHexSecret() throws -> String {
        
        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw SetupCommand.Error.fileOperationFailed("/dev/urandom", CocoaError(.fileReadNoSuchFile))
        }
        
        let data = handle.readData(ofLength: 32)
        try? handle.close()
        
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private func requireResolvableHostname(_ host: String, label: String) async throws {
        if await Shell.run("getent", ["ahosts", host]).exitCode != 0 {
            throw SetupCommand.Error.invalidValue(label, "'\(host)' does not resolve in DNS. Point it to this server before continuing.")
        }
    }

    private func collectAndVerifyGitHubToken() async throws {
        
        while true {
            context.githubToken = console.askSecret("GitHub token")
            do {
                try await verifyGitHubAccess()
                return
            } catch {
                console.warning(error.localizedDescription)
            }
        }
    }

    private func verifyGitHubAccess() async throws {
        
        guard let url = URL(string: "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks?per_page=1")
        else { throw SetupCommand.Error.githubAPI("invalid hooks URL") }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(context.githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SetupCommand.Error.githubAPI("token check failed for \(context.githubOwner)/\(context.githubRepo) (HTTP \(status))")
        }
    }

    private func plannedConfiguration() -> [(String, String)] {
        [
            ("Install directory", paths.installDirectory),
            ("Deployer repo", context.deployerRepositoryURL),
            ("Deployer branch", context.deployerRepositoryBranch),
            ("Service user", context.serviceUser),
            ("Service manager", context.serviceManagerKind.rawValue),
            ("App name", context.appName),
            ("App repo", context.appRepositoryURL),
            ("App branch", context.appBranch),
            ("App directory", paths.appDirectory),
            ("Deployer build mode", context.deployerBuildMode),
            ("App build mode", context.appBuildMode),
            ("Deployer port", "\(context.deployerPort)"),
            ("App port", "\(context.appPort)"),
            ("Panel route", context.panelRoute),
            ("Canonical domain", context.primaryDomain),
            ("Alias domain", context.aliasDomain),
            ("TLS contact", context.tlsContactEmail),
            ("Nginx site file", paths.nginxSiteAvailable),
            ("ACME webroot", paths.acmeWebroot),
            ("Webhook URL", context.webhookURL)
        ]
    }
    
}
