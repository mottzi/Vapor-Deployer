import Vapor

/// Prints the final summary card and operational guidance after a successful setup pipeline execution.
struct SummaryStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Setup complete"

    func run() async throws {

        printSummaryCard()

        if !context.managedAppHealthFailures.isEmpty {
            printManagedAppHealthWarning()
        }
        
        if context.usingStagingCertificates {
            printStagingWarning()
        }
    }

}

extension SummaryStep {

    private func printSummaryCard() {

        var rows = [
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

        if !context.managedAppHealthFailures.isEmpty {
            rows.append(("Managed app health", "degraded - repair required"))
        }
        
        console.card(
            "Setup complete",
            keyedValues: rows
        )
    }

    private func printManagedAppHealthWarning() {

        let failureLines = context.managedAppHealthFailures.map { "Health check: \($0)" }

        console.lines(
            "Managed app health warning",
            lines: failureLines + [
                "Deployer installed successfully, but the managed app did not pass health checks.",
                "Fix \(paths.appDirectory)/.env or the app configuration, then run:",
                "sudo deployerctl restart app",
                "sudo deployerctl status app",
                "sudo deployerctl logs app",
                "Until the app starts, the public app route may return upstream errors."
            ]
        )
    }

    private func printStagingWarning() {

        console.lines(
            "TLS warning - staging certificate in use",
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
