import Vapor

/// Invokes the newly activated deployer binary so deployerctl is rendered from the updated templates.
struct RefreshDeployerctlStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Refreshing operator control wrapper"

    func run() async throws {
        guard context.releaseVersion != context.currentVersion else { return }

        let executableURL = context.stagedBinaryURL.deletingPathExtension()
        let result = await Shell.run(executableURL.path, ["refresh-deployerctl"])
        guard result.exitCode == 0 else { throw DeployerctlInstaller.Error.refreshFailed(result.output) }

        let output = result.output.trimmed
        if !output.isEmpty { console.print(output) }
    }

}
