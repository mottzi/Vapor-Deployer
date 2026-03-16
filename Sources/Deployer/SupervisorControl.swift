import Foundation

struct SupervisorControl {

    static func isRunning(program: String) async -> Bool {
        let output = (try? await shell("supervisorctl status \(program)")) ?? ""
        return output.contains("RUNNING")
    }

    static func restart(program: String) async throws {
        try await shell("supervisorctl restart \(program)")
    }

    static func stop(program: String) async throws {
        try await shell("supervisorctl stop \(program)")
    }

}
