import Vapor
import Mist

/// Operation output stream that fans out to the active delivery sinks while accumulating the final transcript.
actor OperationEventOutput {

    static let streamName = "operation-log"

    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[a-zA-Z]")

    private let app: Application
    private let eventLog: OperationEventLog
    private let deploymentID: UUID?
    private let mistSink: OperationEventMistOutputSink?
    private let consoleSink: OperationEventConsoleOutputSink?

    private(set) var transcript: String

    init(
        app: Application,
        eventLog: OperationEventLog,
        deployment: Deployment,
        priorTranscript: String = "",
        mistSink: OperationEventMistOutputSink? = nil,
        consoleSink: OperationEventConsoleOutputSink? = nil
    ) {
        self.app = app
        self.eventLog = eventLog
        self.deploymentID = deployment.id
        self.transcript = priorTranscript
        self.mistSink = mistSink
        self.consoleSink = consoleSink
    }

    /// Seeds the live stream with any prior transcript before new output begins.
    func start() async {
        await mistSink?.replace(transcript)
        do { try await eventLog.record(.started, deploymentID: deploymentID, payload: transcript) }
        catch { app.logger.error("Failed to start operation output: \(error.localizedDescription)") }
    }

    func append(_ text: String) async {
        guard !text.isEmpty else { return }

        let cleaned = Self.stripAnsi(text)
        guard !cleaned.isEmpty else { return }

        transcript.append(cleaned)
        await mistSink?.append(cleaned)
        consoleSink?.write(cleaned)

        do { try await eventLog.record(.logAppended, deploymentID: deploymentID, payload: cleaned) }
        catch { app.logger.error("Failed to record operation output: \(error.localizedDescription)") }
    }

    func appendLabel(_ label: String) async {
        let prefix = transcript.isEmpty ? "" : "\n"
        await append("\(prefix)──── \(label) ────\n")
    }

    func appendError(_ error: Swift.Error) async {
        if let shellError = error as? Shell.Error {
            await append("\nError: '\(shellError.command)' failed.\n")
        } else {
            await append("\nError: \(error.localizedDescription)\n")
        }
    }

    func flush() async { }

    func close() async {
        await mistSink?.close()
    }

    /// Strips terminal control sequences before logs reach browser or persisted transcript output.
    private static func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

}

/// Direct in-process Mist stream used by server-origin operations.
final class OperationEventMistOutputSink: @unchecked Sendable {

    private let app: Application
    private let component: String
    private let modelID: UUID?

    init(app: Application, deployment: Deployment) {
        self.app = app
        self.component = DeploymentRow.name(for: deployment.product)
        self.modelID = deployment.id
    }

    func replace(_ text: String) async {
        guard let modelID else { return }
        await app.mist.streams.replace(
            component: component,
            modelID: modelID,
            stream: OperationEventOutput.streamName,
            text: text
        )
    }

    func append(_ text: String) async {
        guard let modelID else { return }
        await app.mist.streams.append(
            component: component,
            modelID: modelID,
            stream: OperationEventOutput.streamName,
            text: text
        )
    }

    func close() async {
        guard let modelID else { return }
        await app.mist.streams.close(
            component: component,
            modelID: modelID,
            stream: OperationEventOutput.streamName
        )
    }

}

/// Non-Sendable Console wrapper used from streaming callbacks without spreading unchecked conformance.
final class OperationEventConsoleOutputSink: @unchecked Sendable {

    private let console: any Console

    init(console: any Console) {
        self.console = console
    }

    func write(_ text: String) {
        console.output(text.consoleText(), newLine: false)
    }

}
