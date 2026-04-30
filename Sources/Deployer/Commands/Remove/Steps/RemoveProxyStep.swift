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

    private func removeNginxSiteEnabled() -> Bool {

        guard let path = context.nginxSiteEnabled, !path.isEmpty else { return false }

        guard path.hasPrefix("/etc/nginx/sites-enabled/") else {
            console.warning("Skipping Nginx site entry outside /etc/nginx/sites-enabled: \(path)")
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else { return false }

        try? SystemFileSystem.removeIfPresent(path)
        console.print("Removed Nginx site entry: \(path)")
        return true
    }

    private func removeNginxSiteAvailable() -> Bool {

        guard let path = context.nginxSiteAvailable, !path.isEmpty else { return false }

        guard path.hasPrefix("/etc/nginx/sites-available/") else {
            console.warning("Skipping Nginx site file outside /etc/nginx/sites-available: \(path)")
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else { return false }

        try? SystemFileSystem.removeIfPresent(path)
        console.print("Removed Nginx site file: \(path)")
        return true
    }

    private func removeCertbotRenewHook() -> Bool {

        guard let path = context.certbotRenewHook, !path.isEmpty else { return false }

        guard path.hasPrefix("/etc/letsencrypt/renewal-hooks/deploy/") else {
            console.warning("Skipping renewal hook outside /etc/letsencrypt/renewal-hooks/deploy: \(path)")
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else { return false }

        try? SystemFileSystem.removeIfPresent(path)
        console.print("Removed Certbot renewal hook: \(path)")
        return true
    }

    private func removeAcmeWebroot() -> Bool {

        guard let path = context.acmeWebroot, !path.isEmpty else { return false }

        guard path.hasPrefix("/var/www/certbot/") else {
            console.warning("Skipping ACME webroot cleanup because path is outside /var/www/certbot: \(path)")
            return false
        }

        guard FileManager.default.fileExists(atPath: path) else { return false }

        try? FileManager.default.removeItem(atPath: path)
        console.print("Removed ACME webroot: \(path)")
        return true
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
