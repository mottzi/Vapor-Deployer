import Vapor

/// Removes managed Nginx site files, ACME webroot, and certbot renewal hook, then reloads Nginx.
struct RemoveProxyStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Cleaning reverse proxy artifacts"

    func run() async throws {

        var removedAny = false

        removedAny = removeNginxSiteEnabled() || removedAny
        removedAny = removeNginxSiteAvailable() || removedAny
        removedAny = removeCertbotRenewHook() || removedAny
        removedAny = removeAcmeWebroot() || removedAny

        if !removedAny {
            console.print("Managed reverse-proxy artifacts were not present.")
        }

        await reloadNginxIfPresent()

        console.print("Managed reverse-proxy artifacts cleaned up.")
    }

}

extension RemoveProxyStep {

    private func removeManagedPath(
        _ path: String?,
        requiredPrefix: String,
        outsidePrefixWarning: (String) -> String,
        removedMessage: (String) -> String,
        remove: (String) throws -> Void
    ) -> Bool {

        guard let path, !path.isEmpty else { return false }

        guard path.hasPrefix(requiredPrefix) else {
            console.warning(outsidePrefixWarning(path))
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else { return false }

        try? remove(path)
        console.print(removedMessage(path))
        return true
    }

    private func removeNginxSiteEnabled() -> Bool {
        removeManagedPath(
            context.nginxSiteEnabled,
            requiredPrefix: "/etc/nginx/sites-enabled/",
            outsidePrefixWarning: { "Skipping Nginx site entry outside /etc/nginx/sites-enabled: \($0)" },
            removedMessage: { "Removed Nginx site entry: \($0)" },
            remove: SystemFileSystem.removeIfPresent
        )
    }

    private func removeNginxSiteAvailable() -> Bool {
        removeManagedPath(
            context.nginxSiteAvailable,
            requiredPrefix: "/etc/nginx/sites-available/",
            outsidePrefixWarning: { "Skipping Nginx site file outside /etc/nginx/sites-available: \($0)" },
            removedMessage: { "Removed Nginx site file: \($0)" },
            remove: SystemFileSystem.removeIfPresent
        )
    }

    private func removeCertbotRenewHook() -> Bool {
        removeManagedPath(
            context.certbotRenewHook,
            requiredPrefix: "/etc/letsencrypt/renewal-hooks/deploy/",
            outsidePrefixWarning: { "Skipping renewal hook outside /etc/letsencrypt/renewal-hooks/deploy: \($0)" },
            removedMessage: { "Removed Certbot renewal hook: \($0)" },
            remove: SystemFileSystem.removeIfPresent
        )
    }

    private func removeAcmeWebroot() -> Bool {
        removeManagedPath(
            context.acmeWebroot,
            requiredPrefix: "/var/www/certbot/",
            outsidePrefixWarning: { "Skipping ACME webroot cleanup because path is outside /var/www/certbot: \($0)" },
            removedMessage: { "Removed ACME webroot: \($0)" },
            remove: { try FileManager.default.removeItem(atPath: $0) }
        )
    }

    private func reloadNginxIfPresent() async {

        guard await Shell.run("which nginx").exitCode == 0 else { return }

        if await Shell.run("nginx", ["-t"]).exitCode == 0 {
            await Shell.run("systemctl", ["reload", "nginx"])
            console.print("Reloaded nginx.")
        } else {
            console.warning("Nginx config test failed after cleanup; run 'nginx -t' manually.")
        }
    }

}
