import Foundation

struct Shell {

    @discardableResult
    static func run(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async -> ShellResult {
        
        guard let (process, pipe) = prepareProcess(
            running: command,
            with: arguments,
            in: directory,
            using: environment
        ) else {
            return ShellResult(output: "No command was provided.", exitCode: -1)
        }

        do { try process.run() }
        catch { return ShellResult(output: error.localizedDescription, exitCode: -1) }

        let outputData = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()

        let outputString = String(data: outputData ?? Data(), encoding: .utf8) ?? ""
        return ShellResult(output: outputString, exitCode: process.terminationStatus)
    }

    static func run(_ command: String, directory: String? = nil) async -> ShellResult {
        await run("bash", ["-c", command], directory: directory)
    }

    @discardableResult
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
    static func runThrowing(_ command: String, directory: String? = nil) async throws -> String {

        let result = await run(command, directory: directory)
        return try requireSuccess(result, command: command)
    }

}

extension Shell {

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
    static func requireSuccess(
        _ result: ShellResult,
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

struct ShellResult: Sendable {

    let output: String
    let exitCode: Int32

}
