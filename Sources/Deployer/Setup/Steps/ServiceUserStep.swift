import Vapor
import Foundation

struct ServiceUserStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing service user"

    func run() async throws {
        if await Shell.run("id", ["-u", context.serviceUser]).exitCode == 0 {
            console.print("Reusing existing user '\(context.serviceUser)'.")
        } else {
            try await Shell.runThrowing("useradd", [
                "--system",
                "--create-home",
                "--home-dir", paths.serviceHome,
                "--shell", "/bin/bash",
                context.serviceUser
            ])
            console.print("Created user '\(context.serviceUser)'.")
        }

        _ = try await context.requireServiceUserUID()

        try await SetupFileSystem.installDirectory(paths.serviceHome, owner: context.serviceUser, group: context.serviceUser)
        try await SetupFileSystem.installDirectory(paths.appsRootDirectory, owner: context.serviceUser, group: context.serviceUser)

        if FileManager.default.fileExists(atPath: paths.installDirectory) {
            try await Shell.runThrowing("chown", ["-R", "\(context.serviceUser):\(context.serviceUser)", paths.installDirectory])
        }
    }

}
