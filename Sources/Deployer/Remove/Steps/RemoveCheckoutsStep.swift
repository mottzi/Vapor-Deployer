import Vapor
import Foundation

/// Removes deployer-generated files and the app/deployer checkout directories with strict safety guards.
struct RemoveCheckoutsStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing checkout directories"

    func run() async throws {

        removeDeployerGeneratedFiles()
        removeAppDeployDirectory()
        try removeDirectory(paths.appDirectory, label: "app checkout")
        try removeDirectory(paths.installDirectory, label: "deployer checkout")

        console.print("Checkout directories removed.")
    }

}

extension RemoveCheckoutsStep {

    private func removeDeployerGeneratedFiles() {

        for filename in ["deployer", "deployer.json", "deployer.db", "deployer.log"] {
            try? SystemFileSystem.removeIfPresent("\(paths.installDirectory)/\(filename)")
        }

        console.print("Removed deployer binary, config, database, and log files.")
    }

    private func removeAppDeployDirectory() {

        let deployDir = "\(paths.appDirectory)/deploy"
        guard FileManager.default.fileExists(atPath: deployDir) else { return }
        try? FileManager.default.removeItem(atPath: deployDir)
        console.print("Removed app deploy directory.")
    }

    private func removeDirectory(_ path: String, label: String) throws {

        guard !path.isEmpty else {
            throw RemoveCommand.Error.unsafePath("empty path for \(label)")
        }

        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path

        for denied in ["/", "/home", "/root", paths.serviceHome] {
            guard resolved != denied else {
                throw RemoveCommand.Error.unsafePath("'\(resolved)' for \(label)")
            }
        }

        guard FileManager.default.fileExists(atPath: resolved) else { return }

        console.print("Removing \(label): \(resolved)")
        try FileManager.default.removeItem(atPath: resolved)
    }

}
