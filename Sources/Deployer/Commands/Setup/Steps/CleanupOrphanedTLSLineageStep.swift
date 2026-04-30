import Vapor

/// Optionally deletes a superseded certificate lineage after TLS setup succeeded for the new domain configuration.
struct CleanupOrphanedTLSLineageStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Finalizing TLS lineage cleanup"

    func run() async throws {
        
        guard let oldCertName = context.orphanedCertNameToDelete else { return }
        guard oldCertName != context.certName else { return }
        guard newLineageLooksUsable() else {
            console.warning("Skipping old certificate cleanup because the active lineage '\(context.certName)' is not fully present on disk.")
            return
        }
        
        guard await Shell.run("which", ["certbot"]).exitCode == 0 else {
            console.warning("certbot is not installed; cannot remove old lineage '\(oldCertName)'.")
            return
        }
        
        let previousDomain = context.orphanedPrimaryDomain ?? "the previous domain"
        let question = "Delete old Let's Encrypt certificate lineage '\(oldCertName)' from \(previousDomain)?"
        guard console.confirm(question, defaultYes: false) else {
            console.print("Keeping old certificate lineage '\(oldCertName)'.")
            return
        }
        
        let result = await Shell.run("certbot", ["delete", "--non-interactive", "--cert-name", oldCertName])
        if result.exitCode == 0 {
            console.print("Deleted certificate lineage '\(oldCertName)'.")
        } else {
            console.warning("Could not delete certificate lineage '\(oldCertName)'. It may not exist.")
        }
    }

}

extension CleanupOrphanedTLSLineageStep {

    private func newLineageLooksUsable() -> Bool {
        FileManager.default.fileExists(atPath: "/etc/letsencrypt/live/\(context.certName)/fullchain.pem")
            && FileManager.default.fileExists(atPath: "/etc/letsencrypt/live/\(context.certName)/privkey.pem")
    }

}
