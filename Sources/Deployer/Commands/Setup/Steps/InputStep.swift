import Vapor

/// Gathers all necessary environment, domain, and credential details from the user required to bootstrap the deployment.
struct InputStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Collecting setup values"

    func run() async throws {
        
        let metadata = await ConfigDiscovery.loadDeployerctl()
        context.previousMetadata = metadata
        context.previousBuildFromSource = metadata["BUILD_FROM_SOURCE"].map { $0 == "true" }

        try collectServiceUser(discovered: metadata["SERVICE_USER"])
        
        let jsonConfig = ConfigDiscovery.loadJSON(serviceUser: context.serviceUser)
        let oldSecret = jsonConfig?.webhookSecret
        if let binaryBehaviour = jsonConfig?.target.binaryBehaviour {
            context.binaryBehaviour = binaryBehaviour
        }

        if let existingTesting = jsonConfig?.target.testing {
            context.testing = existingTesting
        }

        if let existingDeploymentMode = jsonConfig?.target.deploymentMode {
            context.deploymentMode = existingDeploymentMode
        }

        if let existingBranch = jsonConfig?.deployerBranch {
            context.deployerRepositoryBranch = existingBranch
        }

        collectTargetRepository(
            discoveredRepo: metadata["APP_REPO_URL"],
            discoveredName: jsonConfig?.target.name ?? metadata["PRODUCT_NAME"] ?? metadata["APP_NAME"]
        )
        collectPorts(
            discoveredDeployer: jsonConfig?.port,
            discoveredApp: metadata["APP_PORT"]
        )
        collectPanelRoute(discovered: jsonConfig?.panelRoute)
        collectServiceBackend(discovered: metadata["SERVICE_BACKEND"])
        collectInstallMode()

        // Depends on serviceUser, appName, and panelRoute being finalized above.
        context.paths = ProvisioningPaths.derive(
            serviceUser: context.serviceUser,
            appName: context.appName,
            panelRoute: context.panelRoute
        )

        collectDeploymentMode()
        collectTestingPolicy()
        collectBinaryBehaviour()
        try collectPanelAuth()
        try await collectDomain(
            discoveredPrimary: metadata["PRIMARY_DOMAIN"],
            discoveredEmail: metadata["TLS_CONTACT_EMAIL"]
        )
        let webhookPlan = try await SetupWebhookPlanner(console: console).collect(
            owner: context.githubOwner,
            repository: context.githubRepo,
            webhookURL: context.webhookURL,
            previousMetadata: context.previousMetadata,
            existingSecret: oldSecret
        )
        context.webhookSecret = webhookPlan.secret
        context.githubToken = webhookPlan.githubToken

        console.card("Planned configuration", keyedValues: plannedConfiguration())
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
                context.appRepositoryWebURL = "https://github.com/\(parsed.owner)/\(parsed.repo)"
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

    private func collectServiceBackend(discovered: String?) {

        console.section("Service manager")

        while true {
            let value = console.askRequired("Service manager", default: discovered ?? "systemd")

            guard let backend = ServiceBackend(rawValue: value) else {
                console.warning("Service manager must be 'systemd' or 'supervisor'.")
                continue
            }

            context.serviceBackend = backend
            break
        }
    }

    private func collectInstallMode() {

        console.section("Install mode")

        context.buildFromSource = console.confirm(
            "Build deployer from source?",
            defaultYes: context.previousBuildFromSource ?? false
        )

        if context.buildFromSource {
            context.deployerRepositoryBranch = console.askRequired(
                "Deployer branch",
                default: context.deployerRepositoryBranch
            )
        }
    }

    private func collectDeploymentMode() {

        console.section("Deployment mode")

        context.deploymentMode = console.confirm(
            "Enable automatic deployments on push?",
            defaultYes: context.deploymentMode == .automatic
        ) ? .automatic : .manual
    }

    private func collectTestingPolicy() {

        console.section("Testing")

        context.testing = console.confirm(
            "Run swift test before each build?",
            defaultYes: context.testing
        )
    }

    private func collectBinaryBehaviour() {

        console.section("Binary retention")
        console.info("Deployment binaries are stored on the server to allow quick rollbacks.")
        console.info("Choose a policy for cleaning up old versions:")
        console.info("- newest:5   Keep a fixed number of recent binaries")
        console.info("- auto:500   Keep binaries until total size exceeds limit (MB)")
        console.info("- all        Indefinite retention")
        console.info("- off       Delete immediately (no rollbacks)")

        while true {
            let value = console.askRequired(
                "Policy",
                default: context.binaryBehaviour.setupValue
            )

            guard let behaviour = BinaryBehaviour.parse(value) else {
                console.warning("Use 'newest:5', 'auto:500', 'all', or 'off'.")
                continue
            }

            context.binaryBehaviour = behaviour
            break
        }
    }

    private func collectPanelAuth() throws {
        console.section("Panel authentication")
        // let panelPassword = console.askSecretConfirmed("Panel password")
        let panelPassword = console.askConfirmed("Panel password")
        context.panelPasswordHash = try Bcrypt.hash(panelPassword)
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

    private func plannedConfiguration() -> [(String, String)] {
        [
            ("Install directory", paths.installDirectory),
            ("Deployer repo", context.deployerRepositoryURL),
            ("Deployer branch", context.deployerRepositoryBranch),
            ("Service user", context.serviceUser),
            ("Service manager", context.serviceBackend.rawValue),
            ("App name", context.appName),
            ("App repo", context.appRepositoryURL),
            ("App repo web URL", context.appRepositoryWebURL),
            ("App branch", context.appBranch),
            ("App directory", paths.appDirectory),
            ("Deployer build mode", context.deployerBuildMode),
            ("App build mode", context.appBuildMode),
            ("Deployment mode", context.deploymentMode.rawValue),
            ("Testing", context.testing ? "swift test before build" : "disabled"),
            ("Binary retention", context.binaryBehaviour.setupValue),
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

    /// Verifies that a domain actively points to this machine before attempting to provision TLS certificates.
    private func requireResolvableDomain(_ domain: String, label: String) async throws {
        
        let isResolvable = await Shell.run("getent", ["ahosts", domain]).exitCode == 0
        if !isResolvable {
            throw Host.Error.invalidValue(
                label,
                "'\(domain)' does not resolve in DNS. Point it to this server before continuing."
            )
        }
    }

}
