import Foundation

extension Deployment {
    
    /// Keeps panel availability and engine enforcement on the same reasoned policy result.
    enum OperationEligibility {
        
        /// Allows both panel presentation and engine execution to proceed.
        case available
        
        /// Preserves the first blocking condition as compound action rules build on shared lifecycle policy.
        case unavailable(UnavailableReason)
        
    }
    
}

extension Deployment.OperationEligibility {
    
    /// Distinguishes lock, lifecycle, and binary-state conflicts without making callers reproduce policy.
    enum UnavailableReason {
        
        case operationLocked
        case live
        case statusBlocksAction
        case alreadyHasSavedBinary
        case missingSavedBinary
        
    }
    
    /// Collapses reasoned policy into the Boolean consumed by panel rendering and engine guards.
    var isAvailable: Bool {
        switch self {
            case .available: true
            case .unavailable: false
        }
    }
    
}

extension Deployment {

    /// Single eligibility policy shared by panel presentation and engine enforcement.
    func eligibility(for action: OperationEngine.Action, holdingLock: Bool) -> OperationEligibility {

        if !holdingLock, OperationLock.isHeld() {
            return .unavailable(.operationLocked)
        }

        switch action {
            case .deploy, .automaticDeploy:
                return deployEligibility

            case .build:
                if isLive { return .unavailable(.live) }
                if case .unavailable(let reason) = deployEligibility { return .unavailable(reason) }
                if hasSavedBinary { return .unavailable(.alreadyHasSavedBinary) }
                return .available

            case .runSavedBinary:
                if isLive { return .unavailable(.live) }
                if case .unavailable(let reason) = deployEligibility { return .unavailable(reason) }
                if !hasSavedBinary { return .unavailable(.missingSavedBinary) }
                return .available

            case .test:
                return switch displayStatus {
                    case .building, .testing, .restoring: .unavailable(.statusBlocksAction)
                    default: .available
                }

            case .delete:
                return isLive ? .unavailable(.live) : .available

            case .removeBinary:
                if isLive { return .unavailable(.live) }
                if !hasSavedBinary { return .unavailable(.missingSavedBinary) }
                return .available
        }
    }

}

extension Deployment {

    /// Blocks active lifecycle states across deploy, build, and restore while allowing stale rows to be retried.
    private var deployEligibility: OperationEligibility {
        switch displayStatus {
            case .building, .testing, .restoring, .running:
                .unavailable(.statusBlocksAction)
            default:
                .available
        }
    }

}
