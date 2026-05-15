import Foundation

extension Queue {

    /// Determines which execution path the queue takes for a given job.
    enum JobMode: Sendable {
        
        /// Full build-and-deploy pipeline, draining any queued pushes in sequence.
        case deploy
        
        /// Build and archive the binary without deploying it live.
        case saveBinary
        
        /// Swap the live binary from a previously saved archive.
        case restoreBinary
        
    }

    /// Outcome returned to callers after attempting to start a queue job.
    enum StartResult: Sendable {
        
        /// Job accepted and running in the background.
        case started
        
        /// Rejected because another job is already in progress.
        case queueBusy
        
        /// Job could not start due to a DB or internal error.
        case failure(String)
        
    }

}
