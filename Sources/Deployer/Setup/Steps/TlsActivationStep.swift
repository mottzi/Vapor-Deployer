import Vapor
import Foundation

struct TlsActivationStep: SetupStep {

    let title = "Activating HTTPS reverse proxy"

    func run(context: SetupContext, console: any Console) async throws {
        try await resolveExistingCertName(context: context, console: console)
        try await issueTLSCertificateWithStagingFallback(context: context, console: console)
        try await resolveCertNameAfterIssue(context: context, console: console)
        context.usingStagingCertificates = await lineageIsStaging(context.certName)

        let paths = try context.requirePaths()
        try await SetupFileSystem.writeFile(try NginxConfigTemplate.tls(context: context), to: paths.nginxSiteAvailable)
        try await SetupFileSystem.installDirectory("/etc/letsencrypt/renewal-hooks/deploy", owner: "root", group: "root")
        try await SetupFileSystem.writeFile(NginxConfigTemplate.renewHookScript(), to: paths.certbotRenewHook, mode: "0755")
        try await Shell.runThrowing(["ln", "-sfn", paths.nginxSiteAvailable, paths.nginxSiteEnabled])
        try await Shell.runThrowing(["nginx", "-t"])
        try await Shell.runThrowing(["systemctl", "reload", "nginx"])
        console.print("HTTPS reverse proxy is active for \(context.primaryDomain).")
    }

    private func issueTLSCertificateWithStagingFallback(context: SetupContext, console: any Console) async throws {
        do {
            try await issueTLSCertificate(
                context: context,
                staging: false,
                forceRenewal: context.currentCertLineageIsStaging
            )
        } catch {
            console.warning("Production Let's Encrypt certificate issuance failed: \(error.localizedDescription)")
            let continueWithStaging = SetupPrompts.confirm(
                "Use Let's Encrypt staging/test certificates and continue setup?",
                defaultYes: true,
                console: console
            )

            guard continueWithStaging else { throw error }

            context.usingStagingCertificates = true
            try await issueTLSCertificate(context: context, staging: true, forceRenewal: context.certLineageFound)
            console.warning("Using Let's Encrypt staging certificates. Browsers will not trust this certificate.")
        }
    }

    private func issueTLSCertificate(context: SetupContext, staging: Bool, forceRenewal: Bool) async throws {
        let paths = try context.requirePaths()
        let emailArguments = context.tlsContactEmail.isEmpty
            ? ["--register-unsafely-without-email"]
            : ["--email", context.tlsContactEmail]
        let serverArguments = staging ? ["--staging"] : []
        let renewalArguments = forceRenewal ? ["--force-renewal"] : ["--keep-until-expiring"]

        try await Shell.runThrowing([
            "certbot", "certonly",
            "--webroot",
            "--agree-tos",
            "--non-interactive"
        ] + serverArguments + emailArguments + [
            "--cert-name", context.certName,
            "--expand",
        ] + renewalArguments + [
            "-w", paths.acmeWebroot,
            "-d", context.primaryDomain,
            "-d", context.aliasDomain
        ])
    }

    private func resolveExistingCertName(context: SetupContext, console: any Console) async throws {
        for name in certificateLineages() {
            if await lineageCoversDomains(name, context: context) {
                context.certName = name
                context.certLineageFound = true
                context.currentCertLineageIsStaging = await lineageIsStaging(name)
                if context.currentCertLineageIsStaging {
                    console.warning("Existing certificate lineage '\(name)' uses Let's Encrypt staging. Attempting to replace it with a production certificate.")
                } else {
                    console.print("Reusing existing certificate lineage '\(name)'.")
                }
                return
            }
        }
    }

    private func resolveCertNameAfterIssue(context: SetupContext, console: any Console) async throws {
        if await lineageFilesOK(context.certName), await lineageCoversDomains(context.certName, context: context) {
            return
        }

        let prefix = "\(context.certName)-"
        let candidates = certificateLineages()
            .filter { $0.hasPrefix(prefix) }
            .sorted()

        for candidate in candidates.reversed() {
            guard await lineageFilesOK(candidate), await lineageCoversDomains(candidate, context: context) else { continue }
            context.certName = candidate
            console.warning("Using certificate lineage '\(candidate)' due to a pre-existing lineage conflict.")
            return
        }

        throw SetupCommand.Error.certificateLineageNotFound(context.primaryDomain, context.aliasDomain)
    }

    private func certificateLineages() -> [String] {
        let directory = "/etc/letsencrypt/live"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return entries.filter { entry in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: "\(directory)/\(entry)", isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private func lineageFilesOK(_ name: String) async -> Bool {
        FileManager.default.fileExists(atPath: "/etc/letsencrypt/live/\(name)/fullchain.pem")
            && FileManager.default.fileExists(atPath: "/etc/letsencrypt/live/\(name)/privkey.pem")
    }

    private func lineageCoversDomains(_ name: String, context: SetupContext) async -> Bool {
        let cert = "/etc/letsencrypt/live/\(name)/fullchain.pem"
        let output = await Shell.run(["openssl", "x509", "-noout", "-text", "-in", cert]).output
        return output.contains("DNS:\(context.primaryDomain)") && output.contains("DNS:\(context.aliasDomain)")
    }

    private func lineageIsStaging(_ name: String) async -> Bool {
        let cert = "/etc/letsencrypt/live/\(name)/fullchain.pem"
        let issuer = await Shell.run(["openssl", "x509", "-noout", "-issuer", "-in", cert]).output
        return issuer.localizedCaseInsensitiveContains("staging")
            || issuer.localizedCaseInsensitiveContains("fake le")
            || issuer.localizedCaseInsensitiveContains("pretend")
    }

}
