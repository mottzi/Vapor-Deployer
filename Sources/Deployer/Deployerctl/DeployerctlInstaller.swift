import Foundation

/// Installs and refreshes the root-owned deployerctl wrapper and its narrow panel-update helper.
enum DeployerctlInstaller {

    static let stagedWrapperName = ".deployerctl.wrapper.new"
    static let stagedConfigName = ".deployerctl.conf.new"

    /// Writes the deployerctl wrapper script, helper, and sudoers configuration directly as the root user.
    static func installRoot(context: DeployerctlInstallContext) async throws {
        
        try await Host.FileSystem.installDirectory(context.deployerctlConfigDirectory, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.configuration(context: context), to: context.deployerctlConfig)
        try await Host.FileSystem.writeFile(DeployerctlTemplate.script(), to: context.deployerctlBinary, mode: "0755")

        try await Host.FileSystem.installDirectory(context.deployerctlHelperDirectory, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.refreshScript(context: context), to: context.deployerctlRefreshHelper, mode: "0755")
        try await Host.FileSystem.installDirectory(URL(fileURLWithPath: context.deployerctlRefreshSudoers).deletingLastPathComponent().path, owner: "root", group: "root")
        try await Host.FileSystem.writeFile(DeployerctlTemplate.refreshSudoers(context: context), to: context.deployerctlRefreshSudoers, mode: "0440")
    }

    /// Reinstalls the deployerctl wrapper, executing either directly as root or via the root-owned helper if unprivileged.
    static func refresh(context: DeployerctlInstallContext) async throws -> RefreshResult {
        
        if Host.User.currentUID == 0 {
            try await installRoot(context: context)
            return .refreshedDirectly
        }

        guard FileManager.default.isExecutableFile(atPath: context.deployerctlRefreshHelper) else {
            return .helperUnavailable
        }

        try writeStagedFiles(context: context)
        let result = await Shell.run("sudo", ["-n", context.deployerctlRefreshHelper])
        guard result.exitCode == 0 else { throw Error.refreshFailed(result.output) }
        return .refreshedWithHelper
    }

}

extension DeployerctlInstaller {
    
    /// Writes new configurations and scripts to temporary staged paths before the root helper moves them into place.
    private static func writeStagedFiles(context: DeployerctlInstallContext) throws {
        
        let installDirectoryURL = URL(fileURLWithPath: context.installDirectory, isDirectory: true)
        let wrapperURL = installDirectoryURL.appendingPathComponent(stagedWrapperName, isDirectory: false)
        let configURL = installDirectoryURL.appendingPathComponent(stagedConfigName, isDirectory: false)

        try DeployerctlTemplate.script().write(to: wrapperURL, atomically: true, encoding: .utf8)
        try DeployerctlTemplate.configuration(context: context).write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: wrapperURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: configURL.path)
    }
    
}

extension DeployerctlInstaller {
    
    /// The outcome of an attempt to refresh the deployerctl wrapper scripts.
    enum RefreshResult {
        
        /// The scripts were updated directly because the current user is already root.
        case refreshedDirectly
        
        /// The scripts were updated successfully by invoking the privileged sudo helper.
        case refreshedWithHelper
        
        /// The refresh was aborted because the required sudo helper is not installed or available.
        case helperUnavailable
        
    }

    /// Errors encountered during the process of updating the deployerctl wrappers.
    enum Error: DescribedError {
        
        /// The invocation of the deployerctl sudo helper failed with the specified output.
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .refreshFailed(let output):
                let trimmed = output.trimmed
                guard !trimmed.isEmpty else { return "Failed to refresh deployerctl wrapper." }
                return "Failed to refresh deployerctl wrapper.\n\(trimmed)"
            }
        }
        
    }
    
}
