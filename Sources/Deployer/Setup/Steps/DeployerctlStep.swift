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
        try await SetupFileSystem.installDirectory(paths.deployerctlConfigDirectory, owner: "root", group: "root")
        try await SetupFileSystem.writeFile(try DeployerctlTemplate.wrapperConfig(context: context), to: paths.deployerctlConfig)
        try await SetupFileSystem.writeFile(DeployerctlTemplate.wrapperScript(), to: paths.deployerctlBinary, mode: "0755")
    }

}
