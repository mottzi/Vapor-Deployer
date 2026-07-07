import Foundation

/// Eliminates the repeated `description`/`debugDescription` boilerplate from error types.
protocol DescribedError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {}

extension DescribedError {
    
    /// A localized message describing the error, prioritizing `errorDescription` over the generic localized fallback.
    var description: String { errorDescription ?? localizedDescription }
    
    /// A detailed representation of the error suitable for debugging, which mirrors the localized description.
    var debugDescription: String { description }
    
}
