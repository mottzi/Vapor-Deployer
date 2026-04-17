import Foundation
import Vapor

/// Runtime configuration for the local deployer, decoded from the sibling JSON file.
struct DeployerConfiguration: Codable, Sendable {
    
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
    
    func makeManager() -> any DeployerServiceManager {
        switch self {
        case .systemd: SystemdServiceManager()
        case .supervisor: SupervisorServiceManager()
        }
    }
    
}

extension DeployerConfiguration {

    /// Loads config from `<executable-name>.json` beside the resolved executable path.
    static func load() throws -> DeployerConfiguration {
        
        let executableURL = try getExecutableURL()
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        
        let configURL = try getConfigURL(forExecutableURL: resolvedExecutableURL)
        let configData: Data
        do { configData = try Data(contentsOf: configURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { throw LoadError.configNotFound(configURL.path) }
        catch { throw LoadError.configUnreadable(configURL.path, error) }

        let configuration: DeployerConfiguration
        do { configuration = try JSONDecoder().decode(DeployerConfiguration.self, from: configData) }
        catch { throw LoadError.invalidJSON(configURL.path, error) }

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
        guard let argument else { throw LoadError.executablePathUnavailable }
        guard !argument.isEmpty else { throw LoadError.executablePathUnavailable }

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
        throw LoadError.executablePathUnavailable
    }

    /// Resolves the sibling `<executable-name>.json` file for the given executable path.
    static func getConfigURL(forExecutableURL executableURL: URL) throws -> URL {
        
        let resolvedExecutableURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        let executableName = resolvedExecutableURL.lastPathComponent

        guard !executableName.isEmpty else { throw LoadError.executablePathUnavailable }

        let executableDirectoryURL = resolvedExecutableURL.deletingLastPathComponent()
        let configFileURL = executableDirectoryURL.appendingPathComponent("\(executableName).json", isDirectory: false)
        return configFileURL
    }

}

extension DeployerConfiguration {

    /// Validates and normalizes decoded config values using the executable directory as the base path.
    func resolved(relativeTo baseDirectoryURL: URL) throws -> DeployerConfiguration {
        
        guard port > 0 else { throw LoadError.invalidField("port", "must be greater than 0") }

        return try DeployerConfiguration(
            port: port,
            dbFile: trimmedFileSystemPath(dbFile, field: "dbFile", relativeTo: baseDirectoryURL),
            socketPath: trimmedValue(socketPath, field: "socketPath"),
            panelRoute: trimmedValue(panelRoute, field: "panelRoute"),
            target: target.resolved(relativeTo: baseDirectoryURL),
            serviceManager: serviceManager
        )
    }

}

extension TargetConfiguration {

    /// Validates and normalizes decoded target values using the executable directory as the base path.
    func resolved(relativeTo baseDirectoryURL: URL) throws -> TargetConfiguration {
        try TargetConfiguration(
            name: trimmedValue(name, field: "target.name"),
            directory: trimmedFileSystemPath(directory, field: "target.directory", relativeTo: baseDirectoryURL),
            buildMode: trimmedValue(buildMode, field: "target.buildMode"),
            pusheventPath: trimmedValue(pusheventPath, field: "target.pusheventPath"),
            deploymentMode: deploymentMode
        )
    }

}

/// Trims surrounding whitespace and rejects empty configuration values.
fileprivate func trimmedValue(_ value: String, field: String) throws -> String {
    
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedValue.isEmpty { return trimmedValue }
    
    throw DeployerConfiguration.LoadError.invalidField(field, "must not be empty")
}

/// Trims and resolves a configured file-system path relative to the executable directory when needed.
fileprivate func trimmedFileSystemPath(_ value: String, field: String, relativeTo baseDirectoryURL: URL) throws -> String {
    
    let trimmedValue = try trimmedValue(value, field: field)
    
    if NSString(string: trimmedValue).isAbsolutePath {
        return URL(fileURLWithPath: trimmedValue).standardizedFileURL.path
    } else {
        return URL(fileURLWithPath: trimmedValue, relativeTo: baseDirectoryURL).absoluteURL.standardizedFileURL.path
    }
}

extension DeployerConfiguration  {
    
    enum LoadError: LocalizedError {
        
        /// Thrown when the process executable path cannot be determined.
        case executablePathUnavailable
        
        /// Thrown when the sibling JSON config file does not exist.
        case configNotFound(String)
        
        /// Thrown when the sibling JSON config file exists but cannot be read.
        case configUnreadable(String, Error)
        
        /// Thrown when the JSON file cannot be decoded into the expected schema.
        case invalidJSON(String, Error)
        
        /// Thrown when a decoded field fails runtime validation.
        case invalidField(String, String)
        
        
        var errorDescription: String? {
            switch self {
            case .executablePathUnavailable:
                "Unable to determine the executable path for Deployer configuration loading."
                
            case .configNotFound(let path):
                "Deployer configuration file not found at '\(path)'."
                
            case .configUnreadable(let path, let error):
                "Failed to read Deployer configuration at '\(path)': \(error.localizedDescription)"
                
            case .invalidJSON(let path, let error):
                "Invalid Deployer configuration JSON at '\(path)': \(error.localizedDescription)"
                
            case .invalidField(let field, let reason):
                "Invalid Deployer configuration field '\(field)': \(reason)"
            }
        }

    }
    
}
