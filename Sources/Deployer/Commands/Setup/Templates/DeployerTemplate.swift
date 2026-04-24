import Foundation

/// Builds the generated runtime `deployer.json` payload from validated setup state and derived install paths.
enum DeployerTemplate {
    
    /// Encodes a canonical deployer configuration snapshot that binds panel routing, webhook path, and managed target metadata.
    static func encodeJSON(from context: SetupContext) throws -> String? {
        
        let paths = try context.requirePaths()
        let config = Configuration(
            port: context.deployerPort,
            dbFile: "deployer.db",
            socketPath: "\(context.panelRoute)/ws",
            panelRoute: context.panelRoute,
            target: TargetConfiguration(
                name: context.productName,
                directory: paths.appDirectoryRelative,
                buildMode: context.appBuildMode,
                pusheventPath: paths.webhookPath,
                deploymentMode: context.deploymentMode
            ),
            serviceManager: context.serviceManagerKind
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        
        return String(data: data, encoding: .utf8)
    }

}
