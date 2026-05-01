import Foundation

/// Builds the generated runtime `deployer.json` payload from validated setup state and derived install paths.
enum DeployerTemplate {
    
    /// Encodes a canonical deployer configuration snapshot that binds panel routing, webhook path, and managed target metadata.
    static func encodeJSON(from context: SetupContext) throws -> String? {
        
        let paths = try context.requirePaths()
        let config = Configuration(
            port: context.deployerPort,
            dbFile: "deployer.db",
            deployerDirectory: ".",
            socketPath: "\(context.panelRoute)/ws",
            panelRoute: context.panelRoute,
            target: TargetConfiguration(
                name: context.productName,
                directory: paths.appDirectoryRelative,
                buildMode: context.appBuildMode,
                pusheventPath: paths.webhookPath,
                deploymentMode: context.deploymentMode,
                appPort: context.appPort,
                branch: context.appBranch
            ),
            serviceManager: context.serviceManagerKind,
            buildFromSource: context.buildFromSource,
            deployerBranch: context.deployerRepositoryBranch,
            webhookSecret: context.webhookSecret.isEmpty ? nil : context.webhookSecret
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        
        return String(data: data, encoding: .utf8)
    }

}
