import Vapor
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CollectInputStep: SetupStep {

    let title = "Collecting setup values"

    func run(context: SetupContext, console: any Console) async throws {
        SetupCard.section("Runtime identity", console: console)
        context.serviceUser = SetupPrompt.askValidated(
            "Dedicated service user",
            default: "vapor",
            warning: "Choose a non-root user containing only letters, numbers, dots, dashes, and underscores.",
            console: console
        ) { $0 != "root" && SetupValidator.isSafeName($0) }

        SetupCard.section("Target repository", console: console)
        while true {
            let repoURL = SetupPrompt.askRequired("Private app repo SSH URL", console: console)
            if let parsed = SetupValidator.parseGitHubSSHURL(repoURL) {
                context.appRepositoryURL = repoURL
                context.githubOwner = parsed.owner
                context.githubRepo = parsed.repo
                break
            }
            console.warning("Use a GitHub SSH URL like git@github.com:owner/repo.git")
        }

        context.appName = SetupPrompt.askValidated(
            "Target app name",
            default: context.githubRepo,
            warning: "App name may contain only letters, numbers, dots, dashes, and underscores.",
            console: console,
            validate: SetupValidator.isSafeName
        )

        SetupCard.section("Ports and routing", console: console)
        context.deployerPort = Int(SetupPrompt.askValidated(
            "Deployer port",
            default: "8081",
            warning: "Deployer port must be a number between 1 and 65535.",
            console: console,
            validate: SetupValidator.isValidPort
        )) ?? 8081

        context.appPort = Int(SetupPrompt.askValidated(
            "Target app port",
            default: "8080",
            warning: "Target app port must be a number between 1 and 65535.",
            console: console,
            validate: SetupValidator.isValidPort
        )) ?? 8080

        while true {
            let panelRoute = SetupValidator.normalizePanelRoute(
                SetupPrompt.askRequired("Panel route", default: "/deployer", console: console)
            )
            guard panelRoute != "/" else {
                console.warning("Panel route '/' is not supported with managed Nginx setup. Use a prefixed route like /deployer.")
                continue
            }
            context.panelRoute = panelRoute
            break
        }

        SetupCard.section("Service manager", console: console)
        while true {
            let value = SetupPrompt.askRequired("Service manager", default: "systemd", console: console)
            guard let kind = ServiceManagerKind(rawValue: value) else {
                console.warning("Service manager must be 'systemd' or 'supervisor'.")
                continue
            }
            context.serviceManagerKind = kind
            break
        }

        context.buildFromSource = SetupPrompt.confirm("Build deployer from source?", defaultYes: false, console: console)
        context.paths = SetupPaths.derive(serviceUser: context.serviceUser, appName: context.appName, panelRoute: context.panelRoute)

        SetupCard.section("Panel authentication", console: console)
        context.panelPassword = SetupPrompt.askSecretConfirmed("Panel password", console: console)
        context.webhookSecret = try generateHexSecret()

        SetupCard.section("Public endpoint", console: console)
        let publicURL = SetupPrompt.askValidated(
            "Public base URL",
            warning: "Public base URL must look like https://example.com (HTTPS + domain only, no path, no port).",
            console: console
        ) { SetupValidator.isValidPublicBaseURL($0) }
        context.publicBaseURL = SetupValidator.normalizeBaseURL(publicURL)
        context.primaryDomain = SetupValidator.extractHost(fromPublicBaseURL: publicURL)
        context.aliasDomain = SetupValidator.deriveAliasDomain(from: context.primaryDomain)
        context.certName = context.primaryDomain

        try await requireResolvableHostname(context.primaryDomain, label: "Canonical domain")
        try await requireResolvableHostname(context.aliasDomain, label: "Alias domain")

        context.tlsContactEmail = SetupPrompt.askValidated(
            "TLS contact email",
            warning: "TLS contact email must be a valid email address.",
            console: console,
            validate: SetupValidator.isValidEmail
        )

        SetupCard.section("GitHub webhook access", console: console)
        SetupCard.card(
            title: "How to create the GitHub token",
            kvs: [
                ("Browser", "https://github.com/settings/tokens"),
                ("Click", "Generate new token > Generate new token (classic)"),
                ("Select", "admin:repo_hook")
            ],
            console: console
        )
        try await collectAndVerifyGitHubToken(context, console: console)

        SetupCard.card(title: "Planned configuration", kvs: try plannedConfiguration(context), console: console)
    }

    private func generateHexSecret() throws -> String {
        guard let handle = FileHandle(forReadingAtPath: "/dev/urandom") else {
            throw SetupCommand.Error.fileOperationFailed("/dev/urandom", CocoaError(.fileReadNoSuchFile))
        }
        let data = handle.readData(ofLength: 32)
        try? handle.close()
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private func requireResolvableHostname(_ host: String, label: String) async throws {
        let result = await Shell.run(["getent", "ahosts", host])
        guard result.exitCode == 0 else {
            throw SetupCommand.Error.invalidValue(label, "'\(host)' does not resolve in DNS. Point it to this server before continuing.")
        }
    }

    private func collectAndVerifyGitHubToken(_ context: SetupContext, console: any Console) async throws {
        while true {
            context.githubToken = SetupPrompt.askSecret("GitHub token", console: console)
            do {
                try await verifyGitHubAccess(context)
                return
            } catch {
                console.warning(error.localizedDescription)
            }
        }
    }

    private func verifyGitHubAccess(_ context: SetupContext) async throws {
        guard let url = URL(string: "https://api.github.com/repos/\(context.githubOwner)/\(context.githubRepo)/hooks?per_page=1") else {
            throw SetupCommand.Error.githubAPI("invalid hooks URL")
        }

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

    private func plannedConfiguration(_ context: SetupContext) throws -> [(String, String)] {
        let paths = try context.requirePaths()
        return [
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
