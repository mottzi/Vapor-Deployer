import Vapor

extension Deployment {

    enum Status: String, Codable, Sendable {
        
        case pushed
        case testing
        case building
        case restoring
        case canceled
        case failed
        case built
        case running
        case stale
        
    }

}
