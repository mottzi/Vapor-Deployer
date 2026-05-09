import Foundation

/// Validation and normalization rules for interactive input so downstream provisioning can assume canonical, host-safe values.
enum InputValidator {

    static func isSafeName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
    
    static func isNonRootSafeName(_ value: String) -> Bool {
        value != "root" && isSafeName(value)
    }

    static func isValidPort(_ value: String) -> Bool {
        guard let port = Int(value) else { return false }
        return (1...65535).contains(port)
    }

    static func isValidEmail(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    static func isValidPublicBaseURL(_ value: String) -> Bool {
        normalizeBaseURL(value).range(of: #"^https://([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+)$"#, options: .regularExpression) != nil
    }

    static func normalizeBaseURL(_ value: String) -> String {
        String(value.trimmed.trimmingSuffix("/")).lowercased()
    }

    static func normalizePanelRoute(_ value: String) -> String {
        var route = value.trimmed
        if !route.hasPrefix("/") { route = "/" + route }
        if route != "/" { route = route.trimmingSuffix("/") }
        return route
    }

    static func parseGitHubSSHURL(_ value: String) -> (owner: String, repo: String)? {
        
        let pattern = #"^git@github\.com:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)(\.git)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range), match.numberOfRanges >= 3 else { return nil }
        guard let ownerRange = Range(match.range(at: 1), in: value) else { return nil }
        guard let repoRange = Range(match.range(at: 2), in: value) else { return nil }
        
        return (String(value[ownerRange]), String(value[repoRange]).trimmingSuffix(".git"))
    }

    static func extractHost(fromPublicBaseURL value: String) -> String {
        String(normalizeBaseURL(value).dropFirst("https://".count))
    }

    static func deriveAliasDomain(from primaryDomain: String) -> String {
        primaryDomain.hasPrefix("www.")
            ? String(primaryDomain.dropFirst("www.".count))
            : "www.\(primaryDomain)"
    }

}
