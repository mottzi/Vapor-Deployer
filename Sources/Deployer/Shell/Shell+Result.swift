import Foundation

extension Shell {
    
    /// Wraps process stdout/stderr output and exit code, parsed by requireSuccess to assert execution success.
    struct Result {

        let output: String
        let exitCode: Int32

    }
    
}
