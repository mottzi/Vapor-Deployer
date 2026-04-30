import Foundation

/// Eliminates the repeated `description`/`debugDescription` boilerplate from error types.
protocol DescribedError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {}

extension DescribedError {
    
    ///
    var description: String { errorDescription ?? localizedDescription }
    
    ///
    var debugDescription: String { description }
    
}
