import Foundation

struct Shell {

    @discardableResult
    /// Spawns a process via prepareProcess to query tool statuses (e.g. check which/dpkg) without throwing errors.
    static func run(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async -> Result {
        
        guard let (process, pipe) = prepareProcess(
            running: command,
            with: arguments,
            in: directory,
            using: environment
        ) else {
            return Result(output: "No command was provided.", exitCode: -1)
        }

        do { try process.run() }
        catch { return Result(output: error.localizedDescription, exitCode: -1) }

        let outputData = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        let outputString = String(data: outputData ?? Data(), encoding: .utf8) ?? ""
        return Result(output: outputString, exitCode: process.terminationStatus)
    }

    /// Evaluates commands in bash for pipe/redirect features (e.g. TCP checks), assuming inputs are pre-sanitized.
    static func run(_ command: String, directory: String? = nil) async -> Result {
        await run("bash", ["-c", command], directory: directory)
    }

    @discardableResult
    /// Runs a command and asserts exit code 0 via requireSuccess, throwing to halt on critical setup failures.
    static func runThrowing(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let result = await run(command, arguments, directory: directory, environment: environment)
        return try requireSuccess(result, command: command, arguments: arguments)
    }

    @discardableResult
    /// Runs a bash command and asserts success via requireSuccess, throwing to abort on download or stage failures.
    static func runThrowing(_ command: String, directory: String? = nil) async throws -> String {

        let result = await run(command, directory: directory)
        return try requireSuccess(result, command: command)
    }

}

extension Shell {

    /// Configures a Process/Pipe with env-lookups and merged contexts, called by run/stream commands on launch.
    static func prepareProcess(
        running command: String,
        with arguments: [String],
        in directory: String?,
        using environment: [String: String]?
    ) -> (Process, Pipe)? {

        let argv = Shell.tokenize(command) + arguments
        guard let executable = argv.first else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.contains("/") ? executable : "/usr/bin/env")
        process.arguments = executable.contains("/") ? Array(argv.dropFirst()) : argv
        
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        if let environment { process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return (process, pipe)
    }

    /// Splits a command string on whitespace so callers can pass a logical command like "git clone" separately from per-call arguments.
    static func tokenize(_ command: String) -> [String] {
        command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    @discardableResult
    /// Validates result.exitCode is 0 to return output, or reconstructs command arguments to throw a Shell.Error.
    static func requireSuccess(
        _ result: Result,
        command: String,
        arguments: [String] = []
    ) throws -> String {

        guard result.exitCode == 0 else {
            let fullCommand = arguments.isEmpty
                ? command
                : (Shell.tokenize(command) + arguments).joined(separator: " ")
            
            throw Error(command: fullCommand, output: result.output)
        }

        return result.output
    }

}
