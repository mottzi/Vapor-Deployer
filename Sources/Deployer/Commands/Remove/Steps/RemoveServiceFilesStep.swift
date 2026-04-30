import Vapor

/// Removes generated systemd unit files and supervisor config files, then reloads the respective daemon.
struct RemoveServiceFilesStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing service files"

    func run() async throws {

        let configurator = context.serviceManagerKind.makeConfigurator(shell: shell, paths: paths)

        if context.serviceManagerKind == .systemd, await userExists() {
            await bestEffort("daemon-reload") {
                try await shell.runUserSystemctl("daemon-reload")
            }
            await bestEffort("disable linger") {
                try await Shell.runThrowing("loginctl", ["disable-linger", context.serviceUser])
            }
        }

        await configurator.removeConfigs(for: ["deployer", context.productName])

        console.print("Service files removed.")
    }

}

extension RemoveServiceFilesStep {

    private func userExists() async -> Bool {
        await UserAccount.exists(context.serviceUser)
    }

}
