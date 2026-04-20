import Vapor
import Foundation

struct DeployerctlInstallStep: SetupStep {

    let title = "Installing operator control wrapper"

    func run(context: SetupContext, console: any Console) async throws {
        
        let paths = try context.requirePaths()
        
        try await SetupFileSystem.installDirectory(paths.deployerctlConfigDirectory, owner: "root", group: "root")
        try await SetupFileSystem.writeFile(try DeployerctlTemplate.wrapperConfig(context: context), to: paths.deployerctlConfig)
        try await SetupFileSystem.writeFile(DeployerctlTemplate.wrapperScript(), to: paths.deployerctlBinary, mode: "0755")
        
        console.print("Installed \(paths.deployerctlBinary).")
    }

}
