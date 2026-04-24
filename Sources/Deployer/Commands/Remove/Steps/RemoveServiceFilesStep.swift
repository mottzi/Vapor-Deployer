import Vapor

/// Removes generated systemd unit files and supervisor config files, then reloads the respective daemon.
struct RemoveServiceFilesStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing service files"

    func run() async throws {

        switch context.serviceManagerKind {
        case .systemd: await removeSystemdFiles()
        case .supervisor: await removeSupervisorFiles()
        }

        console.print("Service files removed.")
    }

}

extension RemoveServiceFilesStep {

    private func removeSystemdFiles() async {

        let unitDir = "\(paths.serviceHome)/.config/systemd/user"

        if await userExists() {
            await bestEffort("daemon-reload") {
                try await shell.runUserSystemctl("daemon-reload")
            }
            await bestEffort("disable linger") {
                try await Shell.runThrowing("loginctl", ["disable-linger", context.serviceUser])
            }
        }

        try? SystemFileSystem.removeIfPresent("\(unitDir)/deployer.service")
        try? SystemFileSystem.removeIfPresent("\(unitDir)/\(context.productName).service")
    }

    private func removeSupervisorFiles() async {

        try? SystemFileSystem.removeIfPresent("/etc/supervisor/conf.d/deployer.conf")
        try? SystemFileSystem.removeIfPresent("/etc/supervisor/conf.d/\(context.productName).conf")

        if await commandExists("supervisorctl") {
            await Shell.run("supervisorctl", ["reread"])
            await Shell.run("supervisorctl", ["update"])
        }
    }

}

extension RemoveServiceFilesStep {

    private func userExists() async -> Bool {
        await UserAccount.exists(context.serviceUser)
    }

    private func commandExists(_ command: String) async -> Bool {
        await Shell.run("which \(command)").exitCode == 0
    }

}
