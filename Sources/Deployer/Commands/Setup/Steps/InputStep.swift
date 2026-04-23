import Vapor

/// Gathers all necessary environment, domain, and credential details from the user required to bootstrap the deployment.
struct InputStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Collecting setup values"

    func run() async throws {
        
        let metadata = await ConfigDiscovery.loadDeployerctl()
        context.previousMetadata = metadata

        try collectServiceUser(discovered: metadata["SERVICE_USER"])
        
        let jsonConfig = ConfigDiscovery.loadJSON(serviceUser: context.serviceUser)

        collectTargetRepository(
            discoveredRepo: metadata["APP_REPO_URL"],
            discoveredName: jsonConfig?.target.name ?? metadata["PRODUCT_NAME"] ?? metadata["APP_NAME"]
        )
        collectPorts(
            discoveredDeployer: jsonConfig?.port,
            discoveredApp: metadata["APP_PORT"]
        )
        collectPanelRoute(discovered: jsonConfig?.panelRoute)
        collectServiceManager(discovered: metadata["SERVICE_MANAGER"])
        try collectPanelAuth()
        try await collectDomain(
            discoveredPrimary: metadata["PRIMARY_DOMAIN"],
            discoveredEmail: metadata["TLS_CONTACT_EMAIL"]
        )
        try await collectGitHubToken()

        console.card(title: "Planned configuration", kvs: plannedConfiguration())
    }

}

extension InputStep {

    private func collectServiceUser(discovered: String?) throws {
        
        console.section("Runtime identity")
                
        if let discovered, !discovered.isEmpty {
            context.serviceUser = discovered
            console.print("Service user is locked to '\(discovered)' from the existing installation. Run 'deployer remove' to change it.")
            return
        }
        
        context.serviceUser = console.askValidated(
            "Dedicated service user",
            default: discovered ?? "vapor",
            warning: "Choose a non-root user containing only letters, numbers, dots, dashes, and underscores.",
            validate: InputValidator.isNonRootSafeName
        )
    }

    private func collectTargetRepository(discoveredRepo: String?, discoveredName: String?) {
        
        console.section("Target repository")
        
        let repoDefault = discoveredRepo ?? ""
        
        while true {
            let repoURL = console.askRequired(
                "Private app repo SSH URL",
                default: repoDefault.isEmpty ? nil : repoDefault
            )
            
            if let parsed = InputValidator.parseGitHubSSHURL(repoURL) {
                context.appRepositoryURL = repoURL
                context.githubOwner = parsed.owner
                context.githubRepo = parsed.repo
                break
            }
            
            console.warning("Use a GitHub SSH URL like git@github.com:owner/repo.git")
        }

        context.appName = console.askValidated(
            "Target app name",
            default: discoveredName ?? context.githubRepo,
            warning: "App name may contain only letters, numbers, dots, dashes, and underscores.",
            validate: InputValidator.isSafeName
        )
    }

    private func collectPorts(discoveredDeployer: Int?, discoveredApp: String?) {
        
        console.section("Ports and routing")
        
        context.deployerPort = Int(console.askValidated(
            "Deployer port",
            default: discoveredDeployer != nil ? "\(discoveredDeployer!)" : "8081",
            warning: "Deployer port must be a number between 1 and 65535.",
            validate: InputValidator.isValidPort
        )) ?? 8081

        context.appPort = Int(console.askValidated(
            "Target app port",
            default: discoveredApp ?? "8080",
            warning: "Target app port must be a number between 1 and 65535.",
            validate: InputValidator.isValidPort
        )) ?? 8080
    }
    
    private func collectPanelRoute(discovered: String?) {
        
        while true {
            var panelRoute = console.askRequired("Panel route", default: discovered ?? "/deployer")
            panelRoute = InputValidator.normalizePanelRoute(panelRoute)
                
            guard panelRoute != "/" else {
                console.warning("Panel route '/' is not supported with managed Nginx setup. Use a prefixed route like /deployer.")
                continue
            }
            
            context.panelRoute = panelRoute
            break
        }
    }

    private func collectServiceManager(discovered: String?) {
        
        console.section("Service manager")
        
        while true {
            let value = console.askRequired("Service manager", default: discovered ?? "systemd")
            
            guard let kind = ServiceManagerKind(rawValue: value) else {
                console.warning("Service manager must be 'systemd' or 'supervisor'.")
                continue
            }
            
            context.serviceManagerKind = kind
            break
        }

        context.buildFromSource = console.confirm("Build deployer from source?", defaultYes: false)
        
        context.paths = SystemPaths.derive(
            serviceUser: context.serviceUser,
            appName: context.appName,
            panelRoute: context.panelRoute
        )
    }

    private func collectPanelAuth() throws {
        console.section("Panel authentication")
        context.panelPassword = console.askSecretConfirmed("Panel password")
        context.webhookSecret = try generateHexSecret()
    }

    private func collectDomain(discoveredPrimary: String?, discoveredEmail: String?) async throws {
        
        console.section("Public endpoint")
        
        let urlDefault = discoveredPrimary != nil ? "https://\(discoveredPrimary!)" : nil
        let publicURL = console.askValidated(
            "Public base URL",
            default: urlDefault,
            warning: "Public base URL must look like https://example.com (HTTPS + domain only, no path, no port).",
            validate: InputValidator.isValidPublicBaseURL
        )
        
        context.publicBaseURL = InputValidator.normalizeBaseURL(publicURL)
        context.primaryDomain = InputValidator.extractHost(fromPublicBaseURL: publicURL)
        context.aliasDomain = InputValidator.deriveAliasDomain(from: context.primaryDomain)
        context.certName = context.primaryDomain

        try await requireResolvableDomain(context.primaryDomain, label: "Canonical domain")
        try await requireResolvableDomain(context.aliasDomain, label: "Alias domain")

        let emailDefault = discoveredEmail ?? ""
        context.tlsContactEmail = console.askValidated(
            "TLS contact email",
            default: emailDefault.isEmpty ? nil : emailDefault,
            warning: "TLS contact email must be a valid email address.",
            validate: InputValidator.isValidEmail
        )
    }

    private func collectGitHubToken() async throws {
        
        console.section("GitHub webhook access")
        
        console.card(
            title: "How to create the GitHub token",
            kvs: [
                ("Browser", "https://github.com/settings/tokens"),
                ("Click", "Generate new token > Generate new token (classic)"),
                ("Select", "admin:repo_hook")
            ]
        )
        
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

extension InputStep {
    
    /// Generates a cryptographically secure 64-character payload used to sign and verify incoming GitHub webhooks.
    private func generateHexSecret() throws -> String {
        
        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw SetupCommand.Error.fileOperationFailed("/dev/urandom", CocoaError(.fileReadNoSuchFile))
        }
        
        let data = handle.readData(ofLength: 32)
        try? handle.close()
        
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies that a domain actively points to this machine before attempting to provision TLS certificates.
    private func requireResolvableDomain(_ domain: String, label: String) async throws {
        
        let isResolvable = await Shell.run("getent", ["ahosts", domain]).exitCode == 0
        if !isResolvable {
            throw SystemError.invalidValue(
                label,
                "'\(domain)' does not resolve in DNS. Point it to this server before continuing."
            )
        }
    }

    /// Asserts that the provided personal access token has sufficient permissions to manage webhooks for the target repository.
    private func verifyGitHubAccess() async throws {
        
        let urlString = "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks?per_page=1"
        guard let url = URL(string: urlString) else {
            throw SetupCommand.Error.githubAPI("invalid hooks URL")
        }

        let (_, status) = try await GitHubAPI.request(url: url, token: context.githubToken)
        guard (200..<300).contains(status) else {
            throw SetupCommand.Error.githubAPI("token check failed for \(context.githubOwner)/\(context.githubRepo) (HTTP \(status))")
        }
    }
    
}
