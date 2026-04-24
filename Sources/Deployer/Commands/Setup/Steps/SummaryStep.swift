import Vapor

/// Prints the final summary card and operational guidance after a successful setup pipeline execution.
struct SummaryStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Setup complete"

    func run() async throws {

        printSummaryCard()
        
        if context.usingStagingCertificates {
            printStagingWarning()
        }
    }

}

extension SummaryStep {

    private func printSummaryCard() {
        
        console.card(
            title: "Setup complete",
            keyedValues: [
                ("Deployer panel", "\(context.publicBaseURL)\(context.panelRoute)"),
                ("Webhook endpoint", context.webhookURL),
                ("Canonical domain", context.primaryDomain),
                ("Alias redirect", "https://\(context.aliasDomain) -> https://\(context.primaryDomain)"),
                ("Certificate", "/etc/letsencrypt/live/\(context.certName)"),
                ("Nginx site", paths.nginxSiteAvailable),
                ("Install dir", paths.installDirectory),
                ("App checkout", paths.appDirectory),
                ("Service user", context.serviceUser),
                ("Service manager", context.serviceManagerKind.rawValue),
                ("Check services", "sudo deployerctl status"),
                ("Follow logs", "sudo deployerctl logs [deployer|app|all]")
            ]
        )
    }

    private func printStagingWarning() {

        console.lines(
            title: "TLS warning - staging certificate in use",
            lines: [
                "The active certificate was issued by Let's Encrypt staging/test infrastructure.",
                "Browsers will show it as untrusted. This is useful for setup testing and rate-limit recovery only.",
                "After the production issuance limit resets or the underlying issue is fixed, rerun:",
                "sudo deployer setup",
                "The setup command detects staging lineages and forces a production certificate replacement.",
                "Manual equivalent:",
                migrationCommand(paths: paths)
            ]
        )
    }

}

extension SummaryStep {

    private func migrationCommand(paths: SystemPaths) -> String {

        let certbot = TemplateEscaping.shellCommand([
            "sudo", "certbot", "certonly",
            "--webroot",
            "--agree-tos",
            "--email", context.tlsContactEmail,
            "--cert-name", context.certName,
            "--expand",
            "--force-renewal",
            "-w", paths.acmeWebroot,
            "-d", context.primaryDomain,
            "-d", context.aliasDomain
        ])

        return "\(certbot) && sudo nginx -t && sudo systemctl reload nginx"
    }

}
