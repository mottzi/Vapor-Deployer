import Foundation

/// Shared utility for discovering existing deployer configurations across setup and remove commands.
struct ConfigDiscovery {
    
    private static let deployerctlKeys = [
        "SERVICE_USER",
        "SERVICE_MANAGER",
        "PRODUCT_NAME",
        "APP_NAME",
        "APP_REPO_URL",
        "APP_PORT",
        "TLS_CONTACT_EMAIL",
        "INSTALL_DIR",
        "APP_DIR",
        "DEPLOYER_LOG",
        "APP_LOG",
        "PRIMARY_DOMAIN",
        "ALIAS_DOMAIN",
        "CERT_NAME",
        "NGINX_SITE_NAME",
        "NGINX_SITE_AVAILABLE",
        "NGINX_SITE_ENABLED",
        "ACME_WEBROOT",
        "CERTBOT_RENEW_HOOK",
        "WEBHOOK_PATH",
        "GITHUB_WEBHOOK_SETTINGS_URL",
        "BUILD_FROM_SOURCE"
    ]

    /// Reads global metadata from the deployerctl configuration file.
    static func loadDeployerctl(configPath: String = "/etc/deployer/deployerctl.conf") async -> [String: String] {
        
        guard FileManager.default.isReadableFile(atPath: configPath) else { return [:] }

        let keyList = deployerctlKeys.joined(separator: " ")
        let script = """
        set -euo pipefail
        config_path="$1"
        keys=(\(keyList))
        # shellcheck disable=SC1090
        source "$config_path"
        
        for key in "${keys[@]}"; do
            if [[ -n "${!key+x}" ]]; then
                printf "%s\\0%s\\0" "$key" "${!key}"
            fi
        done
        """

        let result = await Shell.run("bash", ["-c", script, "bash", configPath])
        guard result.exitCode == 0 else { return [:] }
        
        return parseMetadata(result.output)
    }
    
}

extension ConfigDiscovery {
    
    /// Reads a UTF-8 text file, trims surrounding whitespace/newlines, and returns nil when the file is missing or empty after trimming.
    static func readTrimmedTextFile(at url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = raw.trimmed
        return value.isEmpty ? nil : value
    }
    
    private static func parseMetadata(_ output: String) -> [String: String] {
        var metadata: [String: String] = [:]
        let segments = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        
        var index = 0
        while index + 1 < segments.count {
            let key = segments[index]
            let value = segments[index + 1]
            
            if !key.isEmpty {
                metadata[key] = value
            }
            
            index += 2
        }
        
        return metadata
    }
    
}

extension ConfigDiscovery {

    /// Reads the user-specific runtime configuration from the deployer.json file.
    static func loadJSON(serviceUser: String) -> Configuration? {
        
        let configPath = "/home/\(serviceUser)/deployer/deployer.json"
        guard FileManager.default.isReadableFile(atPath: configPath) else { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return nil }
        guard let config = try? JSONDecoder().decode(Configuration.self, from: data) else { return nil }

        return config
    }

}
