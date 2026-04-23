import Vapor

/// Writes the successful update version and prints the completion message.
struct UpdateSummaryStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Completing update"

    func run() async throws {

        guard let tagName = context.releaseVersion,
              tagName != context.currentVersion else { return }

        writeInstalledVersion(tagName, at: context.versionFileURL)
        
        console.successTitledRule("Deployer update to \(tagName) completed successfully.")
    }

}

extension UpdateSummaryStep {

    /// Persists the installed release tag so future update checks can skip unchanged releases.
    private func writeInstalledVersion(_ version: String, at url: URL) {
        try? version.write(to: url, atomically: true, encoding: .utf8)
    }

}
