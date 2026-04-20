import Vapor
import Foundation

struct PreflightStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Preflight checks"

    func run() async throws {
        let paths = try context.requirePaths()

        if await userExists(context.serviceUser) {
            let home = try await homeDirectory(for: context.serviceUser)
            guard home == paths.serviceHome else {
                throw SetupCommand.Error.invalidValue("serviceUser", "user exists with home '\(home)', not '\(paths.serviceHome)'")
            }
            console.print("Reusing user '\(context.serviceUser)' (home: \(home))")

            if FileManager.default.fileExists(atPath: "\(paths.installDirectory)/.git") {
                if context.buildFromSource {
                    let origin = try await SetupUserShell.runAsServiceUser(context, ["git", "-C", paths.installDirectory, "remote", "get-url", "origin"]).trimmed
                    guard githubRemoteMatches(origin, context.deployerRepositoryURL) else {
                        throw SetupCommand.Error.invalidValue("deployer checkout", "existing origin '\(origin)' does not match '\(context.deployerRepositoryURL)'")
                    }
                    let dirty = try await SetupUserShell.runAsServiceUser(context, ["git", "-C", paths.installDirectory, "status", "--porcelain", "--untracked-files=no"]).trimmed
                    guard dirty.isEmpty else {
                        throw SetupCommand.Error.invalidValue("deployer checkout", "existing checkout has uncommitted changes")
                    }
                }
            } else if FileManager.default.fileExists(atPath: paths.installDirectory), context.buildFromSource {
                if try !isDirectoryEmpty(paths.installDirectory) {
                    throw SetupCommand.Error.invalidValue("installDirectory", "'\(paths.installDirectory)' exists but is not an empty deployer checkout")
                }
            }

            if FileManager.default.fileExists(atPath: "\(paths.appDirectory)/.git") {
                let origin = try await SetupUserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "remote", "get-url", "origin"]).trimmed
                guard githubRemoteMatches(origin, context.appRepositoryURL) else {
                    throw SetupCommand.Error.invalidValue("app checkout", "existing origin '\(origin)' does not match '\(context.appRepositoryURL)'")
                }
                let dirty = try await SetupUserShell.runAsServiceUser(context, ["git", "-C", paths.appDirectory, "status", "--porcelain", "--untracked-files=no"]).trimmed
                guard dirty.isEmpty else {
                    throw SetupCommand.Error.invalidValue("app checkout", "existing checkout has uncommitted changes")
                }
            }
        } else {
            console.print("Service user '\(context.serviceUser)' will be created")
        }

        console.print("Preflight checks passed.")
    }

    private func userExists(_ user: String) async -> Bool {
        await Shell.run(["id", "-u", user]).exitCode == 0
    }

    private func homeDirectory(for user: String) async throws -> String {
        let passwd = try await Shell.runThrowing(["getent", "passwd", user]).trimmed
        let fields = passwd.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6 else { return "" }
        return fields[5]
    }

    private func isDirectoryEmpty(_ path: String) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: path).isEmpty
    }

    private func githubRemoteMatches(_ left: String, _ right: String) -> Bool {
        normalizeGithubRemote(left) == normalizeGithubRemote(right)
    }

    private func normalizeGithubRemote(_ remote: String) -> String {
        var value = remote
        if value.hasSuffix(".git") { value = String(value.dropLast(".git".count)) }
        for prefix in ["https://github.com/", "http://github.com/", "ssh://git@github.com/", "git@github.com:"] {
            if value.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        return value.lowercased()
    }

}
