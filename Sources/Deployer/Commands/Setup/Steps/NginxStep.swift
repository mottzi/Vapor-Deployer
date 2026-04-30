import Vapor

/// Bootstraps Nginx to serve ACME HTTP-01 challenges and removes any previously managed configurations.
struct NginxStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Configuring Nginx for ACME challenge"

    func run() async throws {
        try await cleanupPreviousFiles()
        try await bootstrapNginx()
    }

}

extension NginxStep {

    private func cleanupPreviousFiles() async throws {

        let previousAvailable = context.previousMetadata?["NGINX_SITE_AVAILABLE"]
        let previousEnabled = context.previousMetadata?["NGINX_SITE_ENABLED"]
        let previousHook = context.previousMetadata?["CERTBOT_RENEW_HOOK"]

        if let previousAvailable, previousAvailable != paths.nginxSiteAvailable {
            if let previousEnabled, previousEnabled.hasPrefix("/etc/nginx/sites-enabled/") {
                try? SystemFileSystem.removeIfPresent(previousEnabled)
            }
            if previousAvailable.hasPrefix("/etc/nginx/sites-available/") {
                try? SystemFileSystem.removeIfPresent(previousAvailable)
            }
        }

        if let previousHook,
           previousHook != paths.certbotRenewHook,
           previousHook.hasPrefix("/etc/letsencrypt/renewal-hooks/deploy/") {
            
            try? SystemFileSystem.removeIfPresent(previousHook)
        }
    }

    private func bootstrapNginx() async throws {

        try await SystemFileSystem.installDirectory(paths.acmeWebroot, owner: "root", group: "root")
        try await SystemFileSystem.writeFile(try NginxTemplate.bootstrap(context: context), to: paths.nginxSiteAvailable)
        
        try await Shell.runThrowing(
            "install", [
                "-d", "-m", "0755", "-o", "root", "-g", "root",
                "/etc/nginx/sites-available", 
                "/etc/nginx/sites-enabled"
            ]
        )
        
        try await Shell.runThrowing("ln", ["-sfn", paths.nginxSiteAvailable, paths.nginxSiteEnabled])
        
        try await Shell.runThrowing("systemctl", ["enable", "--now", "nginx"])
        try await Shell.runThrowing("nginx", ["-t"])
        try await Shell.runThrowing("systemctl", ["reload", "nginx"])
        
        console.print("Nginx bootstrap config is active.")
    }

}

