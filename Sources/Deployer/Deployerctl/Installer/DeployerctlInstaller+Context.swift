import Foundation

extension DeployerctlInstaller {

    /// Fully resolved metadata needed to render and install deployerctl without depending on setup-only state.
    struct Context {

        let serviceUser: String
        let serviceBackend: String
        let productName: String
        let appName: String
        let appRepositoryURL: String
        let appPort: String
        let tlsContactEmail: String
        let installDirectory: String
        let appDirectory: String
        let deployerLog: String
        let appLog: String
        let primaryDomain: String
        let aliasDomain: String
        let certName: String
        let nginxSiteName: String
        let nginxSiteAvailable: String
        let nginxSiteEnabled: String
        let acmeWebroot: String
        let certbotRenewHook: String
        let webhookPath: String
        let githubWebhookSettingsURL: String
        let buildFromSource: String
        let deployerctlBinary: String
        let deployerctlConfigDirectory: String
        let deployerctlConfig: String
        let deployerctlHelperDirectory: String
        let deployerctlRefreshHelper: String
        let deployerctlRefreshSudoers: String

    }

}

extension DeployerctlInstaller.Context {

    init(setup context: SetupContext) throws {
        
        let paths = try context.requirePaths()
        
        self.init(
            serviceUser: context.serviceUser,
            serviceBackend: context.serviceBackend.rawValue,
            productName: context.productName,
            appName: context.appName,
            appRepositoryURL: context.appRepositoryURL,
            appPort: String(context.appPort),
            tlsContactEmail: context.tlsContactEmail,
            installDirectory: paths.installDirectory,
            appDirectory: paths.appDirectory,
            deployerLog: paths.deployerLog,
            appLog: "\(paths.appDeployDirectory)/\(context.productName).log",
            primaryDomain: context.primaryDomain,
            aliasDomain: context.aliasDomain,
            certName: context.certName,
            nginxSiteName: paths.nginxSiteName,
            nginxSiteAvailable: paths.nginxSiteAvailable,
            nginxSiteEnabled: paths.nginxSiteEnabled,
            acmeWebroot: paths.acmeWebroot,
            certbotRenewHook: paths.certbotRenewHook,
            webhookPath: paths.webhookPath,
            githubWebhookSettingsURL: "https://github.com/\(context.githubOwner)/\(context.githubRepo)/settings/hooks",
            buildFromSource: String(context.buildFromSource),
            deployerctlBinary: paths.deployerctlBinary,
            deployerctlConfigDirectory: paths.deployerctlConfigDirectory,
            deployerctlConfig: paths.deployerctlConfig,
            deployerctlHelperDirectory: paths.deployerctlHelperDirectory,
            deployerctlRefreshHelper: paths.deployerctlRefreshHelper,
            deployerctlRefreshSudoers: paths.deployerctlRefreshSudoers
        )
    }

    init(
        configuration config: Configuration,
        metadata: [String: String],
        executableURL: URL,
        serviceUser discoveredServiceUser: String?
    ) throws {
        
        let installDirectory = executableURL.deletingLastPathComponent().path
        let serviceUser = try Self.resolveServiceUser(config: config, discovered: discoveredServiceUser)
        let productName = config.target.name
        let appName = Self.first(metadata["APP_NAME"], URL(fileURLWithPath: config.target.directory, isDirectory: true).lastPathComponent, productName)
        let paths = ProvisioningPaths.derive(serviceUser: serviceUser, appName: appName, panelRoute: config.panelRoute)
        let appDirectory = config.target.directory
        let primaryDomain = metadata["PRIMARY_DOMAIN"] ?? ""

        self.init(
            serviceUser: serviceUser,
            serviceBackend: config.serviceBackend.rawValue,
            productName: productName,
            appName: appName,
            appRepositoryURL: Self.first(metadata["APP_REPO_URL"], config.target.repositoryURL),
            appPort: String(config.target.appPort),
            tlsContactEmail: metadata["TLS_CONTACT_EMAIL"] ?? "",
            installDirectory: installDirectory,
            appDirectory: appDirectory,
            deployerLog: "\(installDirectory)/deployer.log",
            appLog: "\(appDirectory)/deploy/\(productName).log",
            primaryDomain: primaryDomain,
            aliasDomain: metadata["ALIAS_DOMAIN"] ?? "",
            certName: metadata["CERT_NAME"] ?? primaryDomain,
            nginxSiteName: metadata["NGINX_SITE_NAME"] ?? paths.nginxSiteName,
            nginxSiteAvailable: metadata["NGINX_SITE_AVAILABLE"] ?? paths.nginxSiteAvailable,
            nginxSiteEnabled: metadata["NGINX_SITE_ENABLED"] ?? paths.nginxSiteEnabled,
            acmeWebroot: metadata["ACME_WEBROOT"] ?? paths.acmeWebroot,
            certbotRenewHook: metadata["CERTBOT_RENEW_HOOK"] ?? paths.certbotRenewHook,
            webhookPath: config.target.pusheventPath,
            githubWebhookSettingsURL: metadata["GITHUB_WEBHOOK_SETTINGS_URL"] ?? "",
            buildFromSource: String(config.buildFromSource),
            deployerctlBinary: paths.deployerctlBinary,
            deployerctlConfigDirectory: paths.deployerctlConfigDirectory,
            deployerctlConfig: paths.deployerctlConfig,
            deployerctlHelperDirectory: paths.deployerctlHelperDirectory,
            deployerctlRefreshHelper: paths.deployerctlRefreshHelper,
            deployerctlRefreshSudoers: paths.deployerctlRefreshSudoers
        )
    }

}

extension DeployerctlInstaller.Context {

    /// Resolves the system user that runs the deployment service, falling back to the configuration file's owner if undiscovered.
    private static func resolveServiceUser(config: Configuration, discovered: String?) throws -> String {
        if let discovered = discovered?.trimmed,
           !discovered.isEmpty {
            return discovered
        }

        let user = URL(fileURLWithPath: config.serviceHome, isDirectory: true).lastPathComponent.trimmed
        guard !user.isEmpty else { throw Host.Error.missingValue("serviceUser") }

        return user
    }

    /// Returns the first non-empty string among the provided candidates, useful for prioritized fallback resolution.
    private static func first(_ candidates: String?...) -> String {
        candidates.compactMap { $0?.trimmed }.first { !$0.isEmpty } ?? ""
    }

}
