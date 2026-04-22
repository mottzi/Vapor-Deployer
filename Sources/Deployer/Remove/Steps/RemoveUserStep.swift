import Vapor

/// Removes the dedicated service user and its home directory after killing all owned processes.
struct RemoveUserStep: RemoveStep {

    let context: RemoveContext
    let console: any Console

    let title = "Removing service user"

    func run() async throws {

        guard await userExists() else {
            console.print("User '\(context.serviceUser)' already absent.")
            return
        }

        console.print("Removing user '\(context.serviceUser)'.")

        await terminateUserSessions()
        await killUserProcesses()
        try await deleteUser()
    }

}

extension RemoveUserStep {

    private func terminateUserSessions() async {
        await Shell.run("loginctl", ["terminate-user", context.serviceUser])
        await Shell.run("loginctl", ["disable-linger", context.serviceUser])
    }

    private func killUserProcesses() async {

        for _ in 0..<10 {
            let pids = await Shell.run("pgrep", ["-u", context.serviceUser]).output.trimmed
            if pids.isEmpty { return }
            await Shell.run("pkill", ["-TERM", "-u", context.serviceUser])
            try? await Task.sleep(for: .seconds(1))
        }

        await Shell.run("pkill", ["-KILL", "-u", context.serviceUser])
    }

    private func deleteUser() async throws {

        for _ in 0..<10 {
            if await Shell.run("userdel", ["-r", context.serviceUser]).exitCode == 0 {
                console.print("Removed user '\(context.serviceUser)'.")
                return
            }

            guard await userExists() else { return }

            await Shell.run("loginctl", ["terminate-user", context.serviceUser])
            await Shell.run("pkill", ["-KILL", "-u", context.serviceUser])
            try? await Task.sleep(for: .seconds(1))
        }

        let remaining = await Shell.run("pgrep", ["-u", context.serviceUser]).output.trimmed
        if !remaining.isEmpty {
            throw RemoveCommand.Error.userDeletionFailed(
                context.serviceUser,
                "active PIDs remain: \(remaining)"
            )
        }

        let result = await Shell.run("userdel", ["-r", context.serviceUser])
        guard result.exitCode == 0 else {
            throw RemoveCommand.Error.userDeletionFailed(
                context.serviceUser,
                result.output.trimmed
            )
        }
    }

}

extension RemoveUserStep {

    private func userExists() async -> Bool {
        await Shell.run("id", ["-u", context.serviceUser]).exitCode == 0
    }

}
