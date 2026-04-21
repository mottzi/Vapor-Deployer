import Vapor
import Foundation

struct NginxStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Configuring Nginx for ACME challenge"

    func run() async throws {
        
        try await cleanupPreviousManagedProxyFiles()
        try await SetupFileSystem.installDirectory(paths.acmeWebroot, owner: "root", group: "root")
        try await SetupFileSystem.writeFile(try NginxTemplate.bootstrap(context: context), to: paths.nginxSiteAvailable)
        try await Shell.runThrowing("install", ["-d", "-m", "0755", "-o", "root", "-g", "root", "/etc/nginx/sites-available", "/etc/nginx/sites-enabled"])
        try await Shell.runThrowing("ln", ["-sfn", paths.nginxSiteAvailable, paths.nginxSiteEnabled])
        try await Shell.runThrowing("systemctl", ["enable", "--now", "nginx"])
        try await Shell.runThrowing("nginx", ["-t"])
        try await Shell.runThrowing("systemctl", ["reload", "nginx"])
        
        console.print("Nginx bootstrap config is active.")
    }

    private func cleanupPreviousManagedProxyFiles() async throws {
        
        let previousAvailable = await readDeployerctlValue("NGINX_SITE_AVAILABLE", configPath: paths.deployerctlConfig)
        let previousEnabled = await readDeployerctlValue("NGINX_SITE_ENABLED", configPath: paths.deployerctlConfig)
        let previousHook = await readDeployerctlValue("CERTBOT_RENEW_HOOK", configPath: paths.deployerctlConfig)

        if let previousAvailable, previousAvailable != paths.nginxSiteAvailable {
            if let previousEnabled, previousEnabled.hasPrefix("/etc/nginx/sites-enabled/") {
                try? SetupFileSystem.removeIfPresent(previousEnabled)
            }
            if previousAvailable.hasPrefix("/etc/nginx/sites-available/") {
                try? SetupFileSystem.removeIfPresent(previousAvailable)
            }
        }

        if let previousHook, previousHook != paths.certbotRenewHook, previousHook.hasPrefix("/etc/letsencrypt/renewal-hooks/deploy/") {
            try? SetupFileSystem.removeIfPresent(previousHook)
        }
    }

    private func readDeployerctlValue(_ key: String, configPath: String) async -> String? {
        
        guard FileManager.default.isReadableFile(atPath: configPath) else { return nil }
        let output = await Shell.run(
            "DEPLOYERCTL_FILE=\(configPath.shellQuoted) DEPLOYERCTL_KEY=\(key.shellQuoted) bash -c 'source \"$DEPLOYERCTL_FILE\"; printf \"%s\" \"${!DEPLOYERCTL_KEY:-}\"'"
        ).output.trimmed
        return output.isEmpty ? nil : output
    }

}
