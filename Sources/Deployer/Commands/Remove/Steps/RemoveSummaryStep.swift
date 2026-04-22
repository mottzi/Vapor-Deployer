import Vapor

/// Prints the final removal summary card with operational follow-up guidance.
struct RemoveSummaryStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removal complete"

    func run() async throws {

        console.successTitledRule("✓ Removal complete")

        console.output("")
        printKV("Service user", "\(context.serviceUser) (removed)")
        printKV("Install dir", "\(paths.installDirectory) (removed)")
        printKV("App dir", "\(paths.appDirectory) (removed)")
        printKV("Nginx site", "\(context.nginxSiteAvailable ?? "—") (removed if present)")
        printKV("ACME webroot", "\(context.acmeWebroot ?? "—") (removed if present)")
        console.output("")

        console.output("  Manual follow-up:".consoleText(isBold: true))
        console.output("    • Delete the GitHub webhook pointing at:".consoleText())

        let webhookPath = context.webhookPath ?? paths.webhookPath
        console.output("      \(webhookPath)".consoleText(color: .cyan))

        if let settingsURL = context.githubWebhookSettingsURL, !settingsURL.isEmpty {
            console.output("      \(settingsURL)".consoleText(color: .cyan))
        } else {
            console.output("      (GitHub repo → Settings → Webhooks)".consoleText())
        }

        console.output("")
    }

}

extension RemoveSummaryStep {

    private func printKV(_ key: String, _ value: String) {
        console.output("  \(key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)".consoleText())
    }

}
