import Foundation

/// How incoming push events should be handled for the configured target.
enum DeploymentMode: String, Codable {
    
    /// Deploy immediately when a valid push event arrives.
    case automatic
    
    /// Record pushes and wait for a manual deploy from the panel.
    case manual
    
}
