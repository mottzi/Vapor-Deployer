import Foundation

extension Configuration {

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

}

enum DeployerJSONTemplate {

    static func configuration(from context: SetupContext) throws -> Configuration {
        let paths = try context.requirePaths()
        return Configuration(
            port: context.deployerPort,
            dbFile: "deployer.db",
            socketPath: paths.deployerSocketPath,
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
    }

}
