import Foundation

extension Shell {

    @discardableResult
    /// Executes a system process and streams its live output to the provided callback.
    static func runStreaming(
        _ command: String,
        _ arguments: [String],
        directory: String? = nil,
        environment: [String: String]? = nil,
        onOutput: @Sendable @escaping (String) async -> Void
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

        let capture = StreamingOutputCapture(onOutput: onOutput)
        
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            capture.append(data)
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
        if !remaining.isEmpty {
            capture.append(remaining)
        }

        await capture.waitForCallbacks()
        
        let result = ShellResult(output: capture.output, exitCode: process.terminationStatus)
        return try Shell.requireSuccess(result, command: command, arguments: arguments)
    }
}

/// Bridges synchronous OS pipe events into a strictly ordered asynchronous stream.
private final class StreamingOutputCapture: @unchecked Sendable {

    private let lock = NSLock()
    private let onOutput: @Sendable (String) async -> Void

    private var captured = Data()
    private var callbackTail: Task<Void, Never>?

    init(onOutput: @Sendable @escaping (String) async -> Void) {
        self.onOutput = onOutput
    }

    /// Provides the complete execution transcript once the process terminates.
    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: captured, encoding: .utf8) ?? ""
    }

    /// Queues process output for ordered, real-time delivery to downstream clients.
    func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)

        lock.lock()
        captured.append(data)
        let previous = callbackTail
        let onOutput = self.onOutput
        
        let task = Task {
            await previous?.value
            guard !text.isEmpty else { return }
            await onOutput(text)
        }
        
        callbackTail = task
        lock.unlock()
    }

    /// Blocks process completion until all pending output has been delivered.
    func waitForCallbacks() async {
        let task = callbackTailSnapshot()
        await task?.value
    }

    /// Captures a thread-safe snapshot of the current delivery queue tail.
    private func callbackTailSnapshot() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        let task = callbackTail
        return task
    }

}
