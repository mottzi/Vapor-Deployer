import Foundation

/// Installs and refreshes the root-owned deployerctl wrapper and its narrow panel-update helper.
enum DeployerctlInstaller {

    /// Writes the deployerctl wrapper script, helper, and sudoers configuration directly as the root user.
    static func installRoot(context: Context) async throws {
        
        try await Host.FileSystem.installDirectory(context.deployerctlConfigDirectory, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.configuration(context: context), to: context.deployerctlConfig)
        try await Host.FileSystem.writeFile(DeployerctlTemplate.script(), to: context.deployerctlBinary, mode: "0755")

        try await Host.FileSystem.installDirectory(context.deployerctlHelperDirectory, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.refreshScript(context: context), to: context.deployerctlRefreshHelper, mode: "0755")
        try await Host.FileSystem.installDirectory(URL(fileURLWithPath: context.deployerctlRefreshSudoers).deletingLastPathComponent().path, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.refreshSudoers(context: context), to: context.deployerctlRefreshSudoers, mode: "0440")
    }

}
