import Vapor
import Foundation

struct SetupCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Installs and provisions the deployer on this host." }

    func run(using context: CommandContext, signature: Signature) async throws {
        try RootGuard.requireRoot()
        try await requireUbuntu()

        let setupContext = SetupContext()
        let steps: [any SetupStep] = [
            CollectInputStep(),
            PreflightStep(),
            PackagesStep(),
            ServiceUserStep(),
            DeployerPayloadStep(),
            SshKeyStep(),
            AppCheckoutStep(),
            ResolveProductStep(),
            SwiftlyStep(),
            BuildStep(),
            WriteRuntimeConfigStep(),
            StartServicesStep(),
            HealthCheckStep(),
            NginxBootstrapStep(),
            TlsActivationStep(),
            DeployerctlInstallStep(),
            GithubWebhookStep(),
            SuccessSummaryStep()
        ]

        for (index, step) in steps.enumerated() {
            step.printHeader(index: index + 1, total: steps.count, console: context.console)
            try await step.run(context: setupContext, console: context.console)
        }
    }

    private func requireUbuntu() async throws {
        let osRelease = (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""
        let id = osRelease
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("ID=") })
            .map { String($0.dropFirst("ID=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            ?? "unknown"

        guard id == "ubuntu" else {
            throw Error.unsupportedOperatingSystem(id)
        }
    }

}
