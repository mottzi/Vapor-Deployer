import Foundation

extension DeployerctlInstaller {

    /// Reinstalls the deployerctl wrapper, executing either directly as root or via the root-owned helper if unprivileged.
    static func refresh(context: Context) async throws -> RefreshResult {
        
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
    
    /// The filename used to stage the replacement deployerctl wrapper before the refresh helper installs it.
    static let stagedWrapperName = ".deployerctl.wrapper.new"
    
    /// The filename used to stage the replacement deployerctl configuration before the refresh helper installs it.
    static let stagedConfigName = ".deployerctl.conf.new"
    
    /// Writes new configurations and scripts to temporary staged paths before the root helper moves them into place.
    private static func writeStagedFiles(context: Context) throws {

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

}
