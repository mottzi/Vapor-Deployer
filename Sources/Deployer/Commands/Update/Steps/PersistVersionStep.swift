import Vapor

/// Persists the candidate version before restart so the new process boots with accurate metadata.
struct PersistVersionStep: UpdateStep {

    let context: UpdateContext
    let console: any Console

    let title = "Persisting version marker"

    func run() async throws {

        guard let version = context.releaseVersion,
              version != context.currentVersion else { return }

        try capturePreviousVersionFile()
        try version.write(to: context.versionFileURL, atomically: true, encoding: .utf8)
        context.versionMarkerAdvanced = true

        console.print("Recorded deployer version \(version).")
    }

}

extension PersistVersionStep {

    private func capturePreviousVersionFile() throws {
        guard !context.versionMarkerAdvanced else { return }

        context.previousVersionFileExisted = FileManager.default.fileExists(atPath: context.versionFileURL.path)
        guard context.previousVersionFileExisted else {
            context.previousVersionFileData = nil
            return
        }

        do {
            context.previousVersionFileData = try Data(contentsOf: context.versionFileURL)
        } catch {
            throw UpdateCommand.Error.versionMarkerCaptureFailed(context.versionFileURL.path, error.localizedDescription)
        }
    }

}
