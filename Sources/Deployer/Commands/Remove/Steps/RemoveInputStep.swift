import Vapor

/// Gathers removal parameters via auto-discovery from deployerctl.conf and deployer.json, prompting for anything unresolved.
struct RemoveInputStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Collecting removal values"

    func run() async throws {

        collectServiceUser()
        await discoverFromDeployerctl()
        discoverFromConfig()
        collectTargetApp()
        collectServiceManager()
        derivePaths()
        deriveProxyMetadata()
        presentSummary()
        try confirmTeardown()
    }

}

extension RemoveInputStep {

    private func collectServiceUser() {

        console.section("Service identity")

        context.serviceUser = console.askValidated(
            "Dedicated service user",
            default: "vapor",
            warning: "Choose a non-root user containing only letters, numbers, dots, dashes, and underscores.",
            validate: InputValidator.isNonRootSafeName
        )

        let passwdPath = "/etc/passwd"
        if let contents = try? String(contentsOfFile: passwdPath, encoding: .utf8),
           let line = contents.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("\(context.serviceUser):") }) {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if fields.count >= 6 {
                console.print("Found user '\(context.serviceUser)' (home: \(fields[5])).")
            }
        } else {
            console.warning("User '\(context.serviceUser)' does not exist — some cleanup steps will be no-ops.")
        }
    }

    private func discoverFromDeployerctl() async {

        let configPath = "/etc/deployer/deployerctl.conf"
        guard FileManager.default.isReadableFile(atPath: configPath) else { return }

        console.print("Discovered deployerctl metadata: \(configPath)")
        
        let metadata = await ConfigDiscovery.loadDeployerctl(configPath: configPath)

        context.nginxSiteAvailable = metadata["NGINX_SITE_AVAILABLE"]
        context.nginxSiteEnabled = metadata["NGINX_SITE_ENABLED"]
        context.acmeWebroot = metadata["ACME_WEBROOT"]
        context.certbotRenewHook = metadata["CERTBOT_RENEW_HOOK"]
        context.webhookPath = metadata["WEBHOOK_PATH"]
        context.githubWebhookSettingsURL = metadata["GITHUB_WEBHOOK_SETTINGS_URL"]
        context.certName = metadata["CERT_NAME"] ?? ""

        if let product = metadata["PRODUCT_NAME"], !product.isEmpty {
            context.productName = product
        }

        if let manager = metadata["SERVICE_MANAGER"],
           let kind = ServiceManagerKind(rawValue: manager) {
            context.serviceManagerKind = kind
        }
    }

    private func discoverFromConfig() {

        let serviceHome = "/home/\(context.serviceUser)"
        let configPath = "\(serviceHome)/deployer/deployer.json"

        guard FileManager.default.isReadableFile(atPath: configPath) else { return }

        console.print("Discovered deployer config: \(configPath)")

        guard let config = ConfigDiscovery.loadJSON(serviceUser: context.serviceUser) else { return }

        if context.productName.isEmpty {
            context.productName = config.target.name
        }

        context.serviceManagerKind = config.serviceManager
    }

    private func collectTargetApp() {

        console.section("Target app")

        let productDefault = context.productName.isEmpty ? "deployer-app" : context.productName

        context.productName = console.askValidated(
            "Target product/service name",
            default: productDefault,
            warning: "Product name may contain only letters, numbers, dots, dashes, and underscores.",
            validate: InputValidator.isSafeName
        )

        let appNameDefault = context.productName
        context.appName = console.askValidated(
            "App name (used for SSH deploy key filename)",
            default: appNameDefault,
            warning: "App name may contain only letters, numbers, dots, dashes, and underscores.",
            validate: InputValidator.isSafeName
        )
    }

    private func collectServiceManager() {

        console.section("Runtime")

        while true {
            let value = console.askRequired("Service manager", default: context.serviceManagerKind.rawValue)
            guard let kind = ServiceManagerKind(rawValue: value) else {
                console.warning("Service manager must be 'systemd' or 'supervisor'.")
                continue
            }
            context.serviceManagerKind = kind
            break
        }
    }

    private func derivePaths() {
        
        context.paths = SystemPaths.derive(
            serviceUser: context.serviceUser,
            appName: context.appName,
            panelRoute: "/deployer"
        )
    }

    private func deriveProxyMetadata() {

        context.nginxSiteAvailable = context.nginxSiteAvailable ?? paths.nginxSiteAvailable
        context.nginxSiteEnabled = context.nginxSiteEnabled ?? paths.nginxSiteEnabled
        context.acmeWebroot = context.acmeWebroot ?? paths.acmeWebroot
        context.certbotRenewHook = context.certbotRenewHook ?? paths.certbotRenewHook
        context.webhookPath = context.webhookPath ?? paths.webhookPath
        context.certName = context.certName.isEmpty ? context.serviceUser : context.certName
    }

    private func presentSummary() {

        console.card(title: "Removal summary", kvs: [
            ("Install dir", paths.installDirectory),
            ("App dir", paths.appDirectory),
            ("Service user", context.serviceUser),
            ("Service manager", context.serviceManagerKind.rawValue),
            ("Product name", context.productName),
            ("App name", context.appName),
            ("Nginx site file", context.nginxSiteAvailable ?? "—"),
            ("ACME webroot", context.acmeWebroot ?? "—"),
            ("Cert lineage", context.certName.isEmpty ? "—" : context.certName),
        ])

        console.output("")
        console.output("  This will (destructive):".consoleText(color: .yellow, isBold: true))
        console.output("    • stop/disable deployer and app services".consoleText())
        console.output("    • remove generated unit/config files".consoleText())
        console.output("    • remove managed Nginx site files, ACME webroot, and renewal hook".consoleText())
        console.output("    • remove operator control wrapper (deployerctl)".consoleText())
        console.output("    • remove deploy SSH key files for this app".consoleText())
        console.output("    • remove deployer and app checkout directories".consoleText())
        console.output("    • remove Linux user and home directory".consoleText())
        console.output("    • optionally delete certificate lineage".consoleText())
        console.output("")
    }

    private func confirmTeardown() throws {

        guard console.confirm("Proceed with teardown?", defaultYes: false) else {
            throw SystemError.invalidValue("confirmation", "Cancelled.")
        }
    }

}

