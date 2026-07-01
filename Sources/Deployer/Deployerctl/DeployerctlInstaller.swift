import Foundation

/// Installs and refreshes the root-owned deployerctl wrapper and its narrow panel-update helper.
enum DeployerctlInstaller {

    static let stagedWrapperName = ".deployerctl.wrapper.new"
    static let stagedConfigName = ".deployerctl.conf.new"

    ///
    static func installRoot(context: DeployerctlInstallContext) async throws {
        
        try await SystemFileSystem.installDirectory(context.deployerctlConfigDirectory, owner: "root", group: "root")
        try await SystemFileSystem.writeFile(DeployerctlTemplate.wrapperConfig(context: context), to: context.deployerctlConfig)
        try await SystemFileSystem.writeFile(DeployerctlTemplate.wrapperScript(), to: context.deployerctlBinary, mode: "0755")

        try await SystemFileSystem.installDirectory(context.deployerctlHelperDirectory, owner: "root", group: "root")
        try await SystemFileSystem.writeFile(DeployerctlTemplate.refreshHelperScript(context: context), to: context.deployerctlRefreshHelper, mode: "0755")
        try await SystemFileSystem.installDirectory(URL(fileURLWithPath: context.deployerctlRefreshSudoers).deletingLastPathComponent().path, owner: "root", group: "root")
        try await SystemFileSystem.writeFile(DeployerctlTemplate.refreshSudoers(context: context), to: context.deployerctlRefreshSudoers, mode: "0440")
    }

    ///
    static func refresh(context: DeployerctlInstallContext) async throws -> RefreshResult {
        
        if UserAccount.currentUID() == 0 {
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
    
    ///
    private static func writeStagedFiles(context: DeployerctlInstallContext) throws {
        
        let installDirectoryURL = URL(fileURLWithPath: context.installDirectory, isDirectory: true)
        let wrapperURL = installDirectoryURL.appendingPathComponent(stagedWrapperName, isDirectory: false)
        let configURL = installDirectoryURL.appendingPathComponent(stagedConfigName, isDirectory: false)

        try DeployerctlTemplate.wrapperScript().write(to: wrapperURL, atomically: true, encoding: .utf8)
        try DeployerctlTemplate.wrapperConfig(context: context).write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: wrapperURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: configURL.path)
    }
    
}

extension DeployerctlInstaller {
    
    ///
    enum RefreshResult {
        
        ///
        case refreshedDirectly
        
        ///
        case refreshedWithHelper
        
        ///
        case helperUnavailable
        
    }

    ///
    enum Error: DescribedError {
        
        ///
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
