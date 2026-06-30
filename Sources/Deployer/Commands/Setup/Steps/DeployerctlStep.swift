import Vapor

/// Installs the `deployerctl` command-line utility and its configuration for operator convenience.
struct DeployerctlStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Installing operator control wrapper"

    func run() async throws {
        try await installDeployerctl()
        console.print("Installed \(paths.deployerctlBinary).")
    }

}

extension DeployerctlStep {

    private func installDeployerctl() async throws {
        try await DeployerctlInstaller.installRoot(context: DeployerctlInstallContext(setup: context))
    }

}
