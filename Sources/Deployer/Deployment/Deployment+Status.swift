import Vapor

extension Deployment {

    enum Status: String, Codable {
        
        case pushed
        case testing
        case building
        case restoring
        case queued
        case failed
        case built
        case running
        case stale
        
    }

}
