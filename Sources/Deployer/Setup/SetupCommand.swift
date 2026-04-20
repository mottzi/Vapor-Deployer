import Vapor

/// Orchestrates host provisioning by running setup steps in a fixed order against one shared context.
struct SetupCommand: AsyncCommand {

    struct Signature: CommandSignature {}

    var help: String { "Installs and provisions the deployer on this host." }
    
    let steps: [any SetupStep] = [
        InputStep(), PreflightStep(), PackagesStep(),
        ServiceUserStep(), DeployerPayloadStep(), SSHStep(),
        AppCheckoutStep(), ResolveProductStep(), SwiftStep(),
        BuildStep(), WriteRuntimeConfigStep(), StartServicesStep(),
        HealthStep(), NginxStep(), TLSStep(),
        DeployerctlStep(), WebhookStep(), SummaryStep()
    ]

    func run(using context: CommandContext, signature: Signature) async throws {
                
        try requireRoot()
        try requireUbuntu()
        
        let setupContext = SetupContext()
        
        context.console.banner()

        for (index, step) in steps.enumerated() {
            step.printHeader(index: index + 1, total: steps.count, console: context.console)
            try await step.run(context: setupContext, console: context.console)
        }
    }
    
    /// Guards distro-specific provisioning (`apt`, `systemd`, Certbot paths) that assumes Ubuntu naming and layout.
    private func requireUbuntu() throws {
        
        let releaseFileText = (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)) ?? ""
        
        let lines = releaseFileText.split(whereSeparator: \.isNewline)
        let line = lines.first(where: { $0.hasPrefix("ID=") })
        let osRaw = line?.dropFirst("ID=".count) ?? "unknown"
        let os = String(osRaw).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard os == "ubuntu" else { throw Error.unsupportedOperatingSystem(os) }
    }
    
    /// Ensures privileged filesystem and service-management operations cannot fail midway under an unprivileged user.
    private func requireRoot() throws {
        guard geteuid() == 0 else { throw SetupCommand.Error.notRoot }
    }

}
