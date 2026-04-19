import Foundation

struct Shell {
    
    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }
        
    @discardableResult static func runThrowing(_ command: String, directory: String? = nil) async throws -> String {
        let result = await run(command, directory: directory)
        guard result.exitCode == 0 else { throw Shell.Error(command: command, output: result.output) }
        return result.output
    }

    @discardableResult static func runThrowing(
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let result = await run(arguments, directory: directory, environment: environment)
        guard result.exitCode == 0 else { throw Shell.Error(command: arguments.joined(separator: " "), output: result.output) }
        return result.output
    }

    static func run(_ command: String, directory: String? = nil) async -> Result {
        await run(["bash", "-c", command], directory: directory)
    }

    static func run(
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async -> Result {

        guard let executable = arguments.first else {
            return Result(output: "No command was provided.", exitCode: -1)
        }

        let process = Process()
        let executablePath = executable.contains("/") ? executable : "/usr/bin/env"
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = executable.contains("/") ? Array(arguments.dropFirst()) : arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Result(output: error.localizedDescription, exitCode: -1)
        }

        async let stdoutData = stdout.fileHandleForReading.readToEnd()
        async let stderrData = stderr.fileHandleForReading.readToEnd()

        process.waitUntilExit()

        let outputData = ((try? await stdoutData) ?? Data()) + ((try? await stderrData) ?? Data())
        let output = String(data: outputData, encoding: .utf8) ?? ""
        return Result(output: output, exitCode: process.terminationStatus)
    }

    
}

extension Shell {
    
    static func getCurrentCheckout(in directory: String) async throws -> GitCheckout {
        
        let commitID = try await runThrowing("git rev-parse HEAD", directory: directory).trimmed
        let commitMessage = try await runThrowing("git log -1 --pretty=%s HEAD", directory: directory).trimmed
        let committedAtRaw = try await runThrowing("git show -s --format=%ct HEAD", directory: directory).trimmed
        
        guard
            let committedAtSeconds = TimeInterval(committedAtRaw),
            commitID.isEmpty == false,
            commitMessage.isEmpty == false
        else {
            throw Shell.Error(command: "git checkout inspection", output: "Failed to parse current checkout metadata.")
        }
        
        let branch = await getCurrentBranch(in: directory)
        
        return GitCheckout(
            commitID: commitID,
            commitMessage: commitMessage,
            branch: branch,
            committedAt: Date(timeIntervalSince1970: committedAtSeconds)
        )
    }
    
    static func getCurrentBranch(in directory: String) async -> String {
        
        let symbolicBranch = await run("git symbolic-ref -q --short HEAD", directory: directory).output.trimmed
        if symbolicBranch.isEmpty == false {
            return "refs/heads/\(symbolicBranch)"
        }
        
        let remoteBranches = await run("git branch -r --contains HEAD --format='%(refname:short)'", directory: directory).output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter {
                $0.isEmpty == false &&
                $0.contains("->") == false &&
                $0.hasSuffix("/HEAD") == false
            }
        
        if let originBranch = remoteBranches.first(where: { $0.hasPrefix("origin/") }) {
            return "refs/heads/\(originBranch.dropFirst("origin/".count))"
        }
        
        return remoteBranches.first ?? "HEAD"
    }
    
}

struct GitCheckout: Sendable {
    
    let commitID: String
    let commitMessage: String
    let branch: String
    let committedAt: Date
    
}
