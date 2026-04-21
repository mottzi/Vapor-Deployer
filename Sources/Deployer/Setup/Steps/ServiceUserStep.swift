import Vapor

/// Prepares the service user for deployment, setting up necessary directories and permissions.
struct ServiceUserStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preparing service user"

    func run() async throws {
        
        try await ensureUserExists()
        try await context.requireServiceUserUID()
        try await prepareDirectories()
        try await ensureInstallDirectoryPermissions()
    }

}

extension ServiceUserStep {

    /// Checks if the service user exists and creates them as a system user if necessary.
    func ensureUserExists() async throws {
        
        if await Shell.run("id", ["-u", context.serviceUser]).exitCode == 0 {
            console.print("Reusing existing user '\(context.serviceUser)'.")
        } else {
            try await Shell.runThrowing(
                "useradd", [
                    "--system",
                    "--create-home",
                    "--home-dir", paths.serviceHome,
                    "--shell", "/bin/bash",
                    context.serviceUser
                ]
            )
            console.print("Created user '\(context.serviceUser)'.")
        }
    }

    /// Creates the service user's home and apps root directories with appropriate ownership.
    func prepareDirectories() async throws {
        
        try await SetupFileSystem.installDirectory(
            paths.serviceHome,
            owner: context.serviceUser,
            group: context.serviceUser
        )
        
        try await SetupFileSystem.installDirectory(
            paths.appsRootDirectory,
            owner: context.serviceUser,
            group: context.serviceUser
        )
    }

    /// Applies the service user's ownership recursively to the installation directory if it exists.
    func ensureInstallDirectoryPermissions() async throws {
        
        if FileManager.default.fileExists(atPath: paths.installDirectory) {
            try await Shell.runThrowing(
                "chown", [
                    "-R", "\(context.serviceUser):\(context.serviceUser)",
                    paths.installDirectory
                ]
            )
        }
    }

}
