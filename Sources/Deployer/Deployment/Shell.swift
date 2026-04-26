import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

struct Shell {
    
    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }
        
    @discardableResult
    static func runThrowing(
        _ command: String,
        directory: String? = nil
    ) async throws -> String {
        
        let result = await run(command, directory: directory)
        guard result.exitCode == 0 else { throw Shell.Error(command: command, output: result.output) }
        return result.output
    }

    @discardableResult
    static func runThrowing(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async throws -> String {

        let result = await run(command, arguments, directory: directory, environment: environment)
        let fullCommand = (Shell.tokenize(command) + arguments).joined(separator: " ")
        guard result.exitCode == 0 else { throw Shell.Error(command: fullCommand, output: result.output) }
        return result.output
    }

    static func run(_ command: String, directory: String? = nil) async -> Result {
        await run("bash", ["-c", command], directory: directory)
    }

    @discardableResult
    static func run(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil
    ) async -> Result {

        let argv = Shell.tokenize(command) + arguments
        guard let executable = argv.first else {
            return Result(output: "No command was provided.", exitCode: -1)
        }

        let process = Process()
        let executablePath = executable.contains("/") ? executable : "/usr/bin/env"
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = executable.contains("/") ? Array(argv.dropFirst()) : argv
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

    static func runStreamingTail(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        tailLineCount: Int = 6,
        redrawInterval: TimeInterval = 0.2,
        forceTTY: Bool? = nil
    ) async -> Result {

        let argv = Shell.tokenize(command) + arguments
        guard let executable = argv.first else {
            return Result(output: "No command was provided.", exitCode: -1)
        }

        let process = Process()
        let executablePath = executable.contains("/") ? executable : "/usr/bin/env"
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = executable.contains("/") ? Array(argv.dropFirst()) : argv
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let renderer = StreamingTailRenderer(
            tailLineCount: tailLineCount,
            redrawInterval: redrawInterval,
            terminalWidth: terminalWidth()
        )
        let shouldRender = forceTTY ?? isStandardOutputTTY()
        let reader = output.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            renderer.append(data, render: shouldRender)
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            return Result(output: error.localizedDescription, exitCode: -1)
        }

        process.waitUntilExit()
        reader.readabilityHandler = nil

        let remaining = reader.readDataToEndOfFile()
        if !remaining.isEmpty {
            renderer.append(remaining, render: shouldRender)
        }

        renderer.finish(render: shouldRender)
        return Result(output: renderer.output, exitCode: process.terminationStatus)
    }

    @discardableResult
    static func runStreamingTailThrowing(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        tailLineCount: Int = 6,
        redrawInterval: TimeInterval = 0.2,
        forceTTY: Bool? = nil
    ) async throws -> String {

        let result = await runStreamingTail(
            command,
            arguments,
            directory: directory,
            environment: environment,
            tailLineCount: tailLineCount,
            redrawInterval: redrawInterval,
            forceTTY: forceTTY
        )
        let fullCommand = (Shell.tokenize(command) + arguments).joined(separator: " ")
        guard result.exitCode == 0 else { throw Shell.Error(command: fullCommand, output: result.output) }
        return result.output
    }

    /// Splits a command string on whitespace so callers can pass a logical command like "git clone" separately from per-call arguments.
    static func tokenize(_ command: String) -> [String] {
        command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

}

private final class StreamingTailRenderer: @unchecked Sendable {

    private let lock = NSLock()
    private let tailLineCount: Int
    private let redrawInterval: TimeInterval
    private let maxLineLength: Int

    private var captured = Data()
    private var pendingLine = ""
    private var tail: [String] = []
    private var renderedLineCount = 0
    private var lastRender = Date.distantPast

    init(tailLineCount: Int, redrawInterval: TimeInterval, terminalWidth: Int) {
        self.tailLineCount = max(tailLineCount, 1)
        self.redrawInterval = redrawInterval
        self.maxLineLength = max(20, terminalWidth - 6)
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: captured, encoding: .utf8) ?? ""
    }

    func append(_ data: Data, render: Bool) {
        lock.lock()
        captured.append(data)
        appendTailLines(from: data)
        if render {
            renderTailIfNeeded(force: false)
        }
        lock.unlock()
    }

    func finish(render: Bool) {
        lock.lock()
        if !pendingLine.isEmpty {
            appendTailLine(pendingLine)
            pendingLine = ""
        }
        if render {
            renderTailIfNeeded(force: true)
            clearRenderedTail()
        }
        lock.unlock()
    }

    private func appendTailLines(from data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let combined = pendingLine + text
        let pieces = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if combined.hasSuffix("\n") {
            pendingLine = ""
            pieces.dropLast().forEach(appendTailLine)
        } else {
            pendingLine = pieces.last ?? ""
            pieces.dropLast().forEach(appendTailLine)
        }
    }

    private func appendTailLine(_ line: String) {
        var normalized = line
        if normalized.hasSuffix("\r") {
            normalized.removeLast()
        }
        tail.append(normalized)
        if tail.count > tailLineCount {
            tail.removeFirst(tail.count - tailLineCount)
        }
    }

    private func renderTailIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastRender) >= redrawInterval else { return }

        clearRenderedTail()
        for line in tail {
            print("    \(truncate(line))")
        }
        fflush(nil)
        renderedLineCount = tail.count
        lastRender = now
    }

    private func clearRenderedTail() {
        guard renderedLineCount > 0 else { return }
        print("\u{1B}[\(renderedLineCount)A\u{1B}[0J", terminator: "")
        fflush(nil)
        renderedLineCount = 0
    }

    private func truncate(_ line: String) -> String {
        guard line.count > maxLineLength else { return line }
        return String(line.prefix(maxLineLength))
    }

}

private func isStandardOutputTTY() -> Bool {
    isatty(STDOUT_FILENO) == 1
}

private func terminalWidth() -> Int {
    TerminalWidth.current()
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
