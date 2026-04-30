import Vapor

/// Prints the final removal summary card with operational follow-up guidance.
struct RemoveSummaryStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removal complete"

    func run() async throws {

        console.successTitledRule("✓ Removal complete")

        console.newLine()
        console.summaryRow("Service user", "\(context.serviceUser) (removed)")
        console.summaryRow("Install dir", "\(paths.installDirectory) (removed)")
        console.summaryRow("App dir", "\(paths.appDirectory) (removed)")
        console.summaryRow("Nginx site", "\(context.nginxSiteAvailable ?? "—") (removed if present)")
        console.summaryRow("ACME webroot", "\(context.acmeWebroot ?? "—") (removed if present)")
        console.newLine()

        console.output("  Manual follow-up:".consoleText(isBold: true))
        console.output("    • Delete the GitHub webhook pointing at:".consoleText())

        let webhookPath = context.webhookPath ?? paths.webhookPath
        console.output("      \(webhookPath)".consoleText(color: .cyan))

        if let settingsURL = context.githubWebhookSettingsURL, !settingsURL.isEmpty {
            console.output("      \(settingsURL)".consoleText(color: .cyan))
        } else {
            console.output("      (GitHub repo → Settings → Webhooks)".consoleText())
        }

        console.newLine()
    }

}
