import Foundation

struct DeployerShell {
    
    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }
        
    @discardableResult static func execute(_ command: String, directory: String? = nil) async throws -> String {
        let result = await run(command, directory: directory)
        guard result.exitCode == 0 else { throw ShellError(command: command, output: result.output) }
        return result.output
    }
    
    @discardableResult static func executeRaw(_ command: String, directory: String? = nil) async -> String {
        await run(command, directory: directory).output
    }
    
    static func executeResult(_ command: String, directory: String? = nil) async -> Result {
        await run(command, directory: directory)
    }
    
    private static func run(_ command: String, directory: String? = nil) async -> Result {
        
        await Task.detached {
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", "-c", command]
            if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            guard (try? process.run()) != nil else { return Result(output: "", exitCode: -1) }
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            return Result(output: output, exitCode: process.terminationStatus)
        }.value
    }

    
}

extension DeployerShell {
    
    static func getCurrentCheckout(in directory: String) async throws -> GitCheckout {
        
        let commitID = try await execute("git rev-parse HEAD", directory: directory).trimmed
        let commitMessage = try await execute("git log -1 --pretty=%s HEAD", directory: directory).trimmed
        let committedAtRaw = try await execute("git show -s --format=%ct HEAD", directory: directory).trimmed
        
        guard
            let committedAtSeconds = TimeInterval(committedAtRaw),
            commitID.isEmpty == false,
            commitMessage.isEmpty == false
        else {
            throw ShellError(command: "git checkout inspection", output: "Failed to parse current checkout metadata.")
        }
        
        let branch = await getCurrentBranch(in: directory)
        
        return GitCheckout(
            commitID: commitID,
            commitMessage: commitMessage,
            branch: branch,
            committedAt: Date(timeIntervalSince1970: committedAtSeconds)
        )
    }
    
    private static func getCurrentBranch(in directory: String) async -> String {
        
        let symbolicBranch = await executeRaw("git symbolic-ref -q --short HEAD", directory: directory).trimmed
        if symbolicBranch.isEmpty == false {
            return "refs/heads/\(symbolicBranch)"
        }
        
        let remoteBranches = await executeRaw("git branch -r --contains HEAD --format='%(refname:short)'", directory: directory)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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

struct ShellError: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
    
    let command: String
    let output: String
    
    var errorDescription: String? {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedOutput.isEmpty == false else {
            return "Command '\(command)' failed."
        }

        return "Command '\(command)' failed.\n\(trimmedOutput)"
    }

    var description: String {
        errorDescription ?? "Shell command failed."
    }

    var debugDescription: String {
        description
    }
    
}

private extension String {
    
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}
