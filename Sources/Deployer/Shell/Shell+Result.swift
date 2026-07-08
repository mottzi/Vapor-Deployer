import Foundation

extension Shell {
    
    /// Immutable container wrapping process terminal output and status code for validation checks.
    struct Result {

        let output: String
        let exitCode: Int32

    }
    
}
