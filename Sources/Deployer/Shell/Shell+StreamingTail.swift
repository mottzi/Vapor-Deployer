import Foundation

extension Shell {

    @discardableResult
    /// Executes a system process and displays a rolling, in-place progress tail in the terminal.
    static func runStreamingTail(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        tailLineCount: Int = 6,
        redrawInterval: TimeInterval = 0.2,
        forceTTY: Bool? = nil
    ) async throws -> String {

        guard let (process, pipe) = prepareProcess(
            running: command,
            with: arguments,
            in: directory,
            using: environment
        ) else {
            return try Shell.requireSuccess(
                ShellResult(output: "No command was provided.", exitCode: -1),
                command: command,
                arguments: arguments
            )
        }

        let renderer = StreamingTailRenderer(
            tailLineCount: tailLineCount,
            redrawInterval: redrawInterval,
            terminalWidth: TerminalWidth.current()
        )
        
        let shouldRender = forceTTY ?? Bool(isatty(STDOUT_FILENO) == 1)
        
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            renderer.append(data, render: shouldRender)
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            return try Shell.requireSuccess(
                ShellResult(output: error.localizedDescription, exitCode: -1),
                command: command,
                arguments: arguments
            )
        }

        process.waitUntilExit()
        reader.readabilityHandler = nil

        let remaining = reader.readDataToEndOfFile()
        if !remaining.isEmpty { renderer.append(remaining, render: shouldRender) }

        renderer.finish(render: shouldRender)
        
        let result = ShellResult(output: renderer.output, exitCode: process.terminationStatus)
        return try Shell.requireSuccess(result, command: command, arguments: arguments)
    }
}

/// Renders a live, rolling window of process output directly to the terminal.
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

    /// Provides the complete execution transcript once the process terminates.
    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: captured, encoding: .utf8) ?? ""
    }

    /// Queues incoming process output and triggers a terminal redraw if the throttle interval has elapsed.
    func append(_ data: Data, render: Bool) {
        lock.lock()
        captured.append(data)
        appendTailLines(from: data)
        if render { renderTailIfNeeded(force: false) }
        lock.unlock()
    }

    /// Flushes remaining output and clears the rolling tail block from the terminal.
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

    /// Splits raw data into individual lines, buffering any incomplete trailing segment for the next chunk.
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

    /// Normalizes and appends a single line to the rolling window, evicting the oldest if necessary.
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

    /// Redraws the current rolling window if the throttle interval has elapsed or a redraw is forced.
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

    /// Erases the currently rendered lines from the terminal to prepare for a fresh redraw.
    private func clearRenderedTail() {
        guard renderedLineCount > 0 else { return }
        print("\u{1B}[\(renderedLineCount)A\u{1B}[0J", terminator: "")
        fflush(nil)
        renderedLineCount = 0
    }

    /// Shortens a line to prevent terminal wrapping that would break vertical cursor positioning.
    private func truncate(_ line: String) -> String {
        guard line.count > maxLineLength else { return line }
        return String(line.prefix(maxLineLength))
    }

}
