import Vapor

/// Removes the operator control wrapper script and its configuration.
struct RemoveDeployerctlStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing operator control wrapper"

    func run() async throws {

        var removedAny = false

        if removeFile(paths.deployerctlBinary) {
            console.print("Removed \(paths.deployerctlBinary).")
            removedAny = true
        }

        if removeFile(paths.deployerctlConfig) {
            console.print("Removed \(paths.deployerctlConfig).")
            removedAny = true
        }

        removeEmptyDirectory(paths.deployerctlConfigDirectory)

        if !removedAny {
            console.print("Operator control wrapper was not present.")
        }

        console.print("Operator control wrapper cleaned up.")
    }

}

extension RemoveDeployerctlStep {

    private func removeFile(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        try? FileManager.default.removeItem(atPath: path)
        return true
    }

    /// Removes a directory only if it is empty — leaves it in place if operators added custom files.
    private func removeEmptyDirectory(_ path: String) {

        guard FileManager.default.fileExists(atPath: path) else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path),
              contents.isEmpty else { return }

        try? FileManager.default.removeItem(atPath: path)
        console.print("Removed \(path).")
    }

}
