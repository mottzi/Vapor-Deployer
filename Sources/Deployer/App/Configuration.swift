import Vapor

/// Runtime configuration for the local deployer, decoded from the sibling JSON file.
struct Configuration: Codable, Sendable {
    
    let port: Int
    let dbFile: String
    let socketPath: String
    let panelRoute: String
    let target: TargetConfiguration
    let serviceManager: ServiceManagerKind
    
}

/// Runtime configuration for the single deployment target managed by the deployer.
struct TargetConfiguration: Codable, Sendable {
    
    let name: String
    let directory: String
    let buildMode: String
    let pusheventPath: String
    let deploymentMode: DeploymentMode
    
}

/// How incoming push events should be handled for the configured target.
enum DeploymentMode: String, Codable, Sendable {
    
    /// Deploy immediately when a valid push event arrives.
    case automatic
    
    /// Record pushes and wait for a manual deploy from the panel.
    case manual
    
}

/// The underlying service manager used to control the deployed application.
enum ServiceManagerKind: String, Codable, Sendable {
    
    /// Comes preinstalled with Ubuntu.
    case systemd
    
    /// Is easier to use than systemd but requires dependency.
    case supervisor
    
    func makeManager(serviceUser: String? = nil) -> any ServiceManager {
        switch self {
        case .systemd: SystemdServiceManager(serviceUser: serviceUser)
        case .supervisor: SupervisorServiceManager()
        }
    }
    
}

extension Configuration {

    /// Loads config from `<executable-name>.json` beside the resolved executable path.
    static func load() throws -> Configuration {
        
        let executableURL = try getExecutableURL()
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        
        let configURL = try getConfigURL(forExecutableURL: resolvedExecutableURL)
        let configData: Data
        do { configData = try Data(contentsOf: configURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { throw Error.configNotFound(configURL.path) }
        catch { throw Error.configUnreadable(configURL.path, error) }

        let configuration: Configuration
        do { configuration = try JSONDecoder().decode(Configuration.self, from: configData) }
        catch { throw Error.invalidJSON(configURL.path, error) }

        let executableDirectoryURL = resolvedExecutableURL.deletingLastPathComponent()
        return try configuration.resolved(relativeTo: executableDirectoryURL)
    }

    /// Uses the resolved binary path as the config anchor so symlinked installs behave predictably.
    static func getExecutableURL() throws -> URL {
        
        let fileManager = FileManager.default
        
        // Prefer the runtime-provided executable URL when it is available.
        if let executableURL = Bundle.main.executableURL {
            return executableURL.standardizedFileURL.resolvingSymlinksInPath()
        }

        // Fall back to argv[0] when Bundle cannot tell us where the binary lives.
        let argument = ProcessInfo.processInfo.arguments.first
        guard let argument else { throw Error.executablePathUnavailable }
        guard !argument.isEmpty else { throw Error.executablePathUnavailable }

        // Treat slash-containing argv[0] values as direct paths from the launch context.
        if argument.contains("/") {
            let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            let executableURL = URL(fileURLWithPath: argument, relativeTo: currentDirectoryURL).absoluteURL
            return executableURL.standardizedFileURL.resolvingSymlinksInPath()
        }

        // Otherwise search PATH the same way a shell-style launch would.
        let pathVariable = Environment.get("PATH") ?? ""
        for directory in pathVariable.split(separator: ":") {
            let candidateURL = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(argument, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL.standardizedFileURL.resolvingSymlinksInPath()
            }
        }

        // If none of those paths resolve, the binary location is unknown.
        throw Error.executablePathUnavailable
    }

    /// Resolves the sibling `<executable-name>.json` file for the given executable path.
    static func getConfigURL(forExecutableURL executableURL: URL) throws -> URL {
        
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let executableName = resolvedExecutableURL.lastPathComponent

        guard !executableName.isEmpty else { throw Error.executablePathUnavailable }

        let executableDirectoryURL = resolvedExecutableURL.deletingLastPathComponent()
        let configFileURL = executableDirectoryURL.appendingPathComponent("\(executableName).json", isDirectory: false)
        return configFileURL
    }

}

extension Configuration {

    /// Validates and normalizes decoded config values using the executable directory as the base path.
    func resolved(relativeTo baseDirectoryURL: URL) throws -> Configuration {
        
        guard port > 0 else { throw Error.invalidField("port", "must be greater than 0") }

        return try Configuration(
            port: port,
            dbFile: Configuration.trimmedFileSystemPath(dbFile, field: "dbFile", relativeTo: baseDirectoryURL),
            socketPath: Configuration.trimmedValue(socketPath, field: "socketPath"),
            panelRoute: Configuration.trimmedValue(panelRoute, field: "panelRoute"),
            target: target.resolved(relativeTo: baseDirectoryURL),
            serviceManager: serviceManager
        )
    }

}

extension TargetConfiguration {

    /// Validates and normalizes decoded target values using the executable directory as the base path.
    func resolved(relativeTo baseDirectoryURL: URL) throws -> TargetConfiguration {
        try TargetConfiguration(
            name: Configuration.trimmedValue(name, field: "target.name"),
            directory: Configuration.trimmedFileSystemPath(directory, field: "target.directory", relativeTo: baseDirectoryURL),
            buildMode: Configuration.trimmedValue(buildMode, field: "target.buildMode"),
            pusheventPath: Configuration.trimmedValue(pusheventPath, field: "target.pusheventPath"),
            deploymentMode: deploymentMode
        )
    }

}

extension Configuration {

    fileprivate static func trimmedValue(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { throw Error.invalidField(field, "must not be empty") }
        return trimmed
    }

    fileprivate static func trimmedFileSystemPath(_ value: String, field: String, relativeTo baseDirectoryURL: URL) throws -> String {
        let trimmed = try trimmedValue(value, field: field)
        return PathComparison.standardizedPath(trimmed, relativeTo: baseDirectoryURL)
    }

}
