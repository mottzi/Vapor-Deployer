import Foundation

/// Shared path normalization and comparison helpers using standardized URL path semantics.
enum PathComparison {

    /// Normalizes a path using `.standardizedFileURL.path` without resolving symlinks.
    static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Normalizes an absolute or base-relative path using `.standardizedFileURL.path` without resolving symlinks.
    static func standardizedPath(_ path: String, relativeTo baseDirectoryURL: URL) -> String {
        if NSString(string: path).isAbsolutePath {
            return standardizedPath(path)
        } else {
            return URL(fileURLWithPath: path, relativeTo: baseDirectoryURL).absoluteURL.standardizedFileURL.path
        }
    }

    /// Compares two filesystem paths after `.standardizedFileURL` normalization.
    static func isSamePath(_ lhs: String, _ rhs: String) -> Bool {
        standardizedPath(lhs) == standardizedPath(rhs)
    }

}
