import Vapor

/// Prints the completion message after the update has been activated and verified.
struct UpdateSummaryStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Completing update"

    func run() async throws {

        guard let tagName = context.releaseVersion,
              tagName != context.currentVersion else { return }
        
        console.successTitledRule("Deployer update to \(tagName) completed successfully.")
    }

}
