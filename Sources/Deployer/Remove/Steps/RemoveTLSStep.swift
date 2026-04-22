import Vapor

/// Optionally removes the managed Let's Encrypt certificate lineage after user confirmation.
struct RemoveTLSStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "TLS certificate cleanup"

    func run() async throws {

        guard !context.certName.isEmpty else {
            console.print("No managed certificate name configured; skipping cert deletion prompt.")
            return
        }

        guard console.confirm("Delete Let's Encrypt certificate '\(context.certName)' as well?", defaultYes: false) else {
            console.print("Keeping certificate lineage '\(context.certName)'.")
            return
        }

        await bestEffort("delete certificate") {
            try await deleteCertificate()
        }
    }

}

extension RemoveTLSStep {

    private func deleteCertificate() async throws {

        guard await Shell.run("which certbot").exitCode == 0 else {
            console.warning("certbot is not installed; cannot remove certificate '\(context.certName)'.")
            return
        }

        let result = await Shell.run("certbot", ["delete", "--non-interactive", "--cert-name", context.certName])

        if result.exitCode == 0 {
            console.print("Deleted certificate lineage '\(context.certName)'.")
        } else {
            console.warning("Could not delete certificate lineage '\(context.certName)'. It may not exist.")
        }
    }

}
