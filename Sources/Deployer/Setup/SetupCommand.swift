import Vapor

struct SetupCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Installs and provisions the deployer on this host." }
    
    let steps: [any SetupStep] = [
        CollectInputStep(), PreflightStep(), PackagesStep(),
        ServiceUserStep(), DeployerPayloadStep(), SshKeyStep(),
        AppCheckoutStep(), ResolveProductStep(), SwiftlyStep(),
        BuildStep(), WriteRuntimeConfigStep(), StartServicesStep(),
        HealthCheckStep(), NginxBootstrapStep(), TlsActivationStep(),
        DeployerctlInstallStep(), GithubWebhookStep(), SuccessSummaryStep()
    ]

    func run(using context: CommandContext, signature: Signature) async throws {
                
        try requireRoot()
        try requireUbuntu()
        
        let setupContext = SetupContext()
        
        SetupCards.banner(console: context.console)

        for (index, step) in steps.enumerated() {
            step.printHeader(index: index + 1, total: steps.count, console: context.console)
            try await step.run(context: setupContext, console: context.console)
        }
    }
    
    private func requireUbuntu() throws {
        
        let releaseFileText = (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""
        
        let lines = releaseFileText.split(whereSeparator: \.isNewline)
        let line = lines.first(where: { $0.hasPrefix("ID=") })
        let osRaw = line?.dropFirst("ID=".count) ?? "unknown"
        let os = String(osRaw).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard os == "ubuntu" else { throw Error.unsupportedOperatingSystem(os) }
    }
    
    private func requireRoot() throws {
        guard geteuid() == 0 else { throw SetupCommand.Error.notRoot }
    }

}
