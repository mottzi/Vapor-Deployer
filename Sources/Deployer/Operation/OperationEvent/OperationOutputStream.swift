import Vapor
import Mist

/// Operation output stream that fans out to the active delivery sinks while accumulating the final transcript.
actor OperationOutputStream {
    
    static let streamName = "operation-log"
    
    private let app: Application
    private let recorder: OperationEventRecorder
    private let deploymentID: UUID?
    private let mistSink: OperationOutputMistSink?
    private let consoleSink: OperationOutputConsoleSink?
    
    private(set) var transcript: String
    
    init(
        app: Application,
        recorder: OperationEventRecorder,
        deployment: Deployment,
        priorTranscript: String = "",
        mistSink: OperationOutputMistSink? = nil,
        consoleSink: OperationOutputConsoleSink? = nil
    ) {
        self.app = app
        self.recorder = recorder
        self.deploymentID = deployment.id
        self.transcript = priorTranscript
        self.mistSink = mistSink
        self.consoleSink = consoleSink
    }
    
    /// Seeds the live stream with any prior transcript before new output begins.
    func open() async {
        await mistSink?.replace(transcript)
        do { try await recorder.record(.outputOpened, deploymentID: deploymentID, payload: transcript) }
        catch { app.logger.error("Failed to open operation output: \(error.localizedDescription)") }
    }
    
    /// Closes streaming delivery sinks to signal the completion of operational logging.
    func close() async {
        await mistSink?.close()
    }
    
    /// Appends formatted, ANSI-stripped text to the log transcript, broadcasting it to console, web streams, and database records.
    func append(_ text: String) async {
        
        guard !text.isEmpty else { return }
        let cleaned = LogSanitizer.sanitize(text)
        guard !cleaned.isEmpty else { return }
        
        transcript.append(cleaned)
        await mistSink?.append(cleaned)
        consoleSink?.write(cleaned)
        
        do { try await recorder.record(.logAppended, deploymentID: deploymentID, payload: cleaned) }
        catch { app.logger.error("Failed to record operation output: \(error.localizedDescription)") }
    }
    
    /// Appends a structured header separator to visually divide distinct phases in the output transcript.
    func appendLabel(_ label: String) async {
        let prefix = transcript.isEmpty ? "" : "\n"
        await append("\(prefix)──── \(label) ────\n")
    }
    
    /// Formats and logs a command execution failure or application error message directly to the transcript.
    func appendError(_ error: Swift.Error) async {
        if let shellError = error as? Shell.Error {
            await append("\nError: '\(shellError.command)' failed.\n")
        } else {
            await append("\nError: \(error.localizedDescription)\n")
        }
    }
    
}

/// Direct in-process Mist stream used by server-origin operations.
final class OperationOutputMistSink: @unchecked Sendable {

    private let app: Application
    private let component: String
    private let modelID: UUID?

    init(app: Application, deployment: Deployment) {
        self.app = app
        self.component = DeploymentRow.name(for: deployment.product)
        self.modelID = deployment.id
    }

    /// Overwrites the entire contents of the active real-time web stream with new content.
    func replace(_ text: String) async {
        guard let modelID else { return }
        await app.mist.streams.replace(
            component: component,
            modelID: modelID,
            stream: OperationOutputStream.streamName,
            text: text
        )
    }

    /// Pushes a text segment to the real-time web stream for incremental display.
    func append(_ text: String) async {
        guard let modelID else { return }
        await app.mist.streams.append(
            component: component,
            modelID: modelID,
            stream: OperationOutputStream.streamName,
            text: text
        )
    }

    /// Terminates the real-time web stream, preventing further client-side appending.
    func close() async {
        guard let modelID else { return }
        await app.mist.streams.close(
            component: component,
            modelID: modelID,
            stream: OperationOutputStream.streamName
        )
    }

}

/// Non-Sendable Console wrapper used from streaming callbacks without spreading unchecked conformance.
final class OperationOutputConsoleSink: @unchecked Sendable {

    private let console: any Console

    init(console: any Console) {
        self.console = console
    }

    /// Writes a raw text snippet directly to the terminal stdout without adding a newline.
    func write(_ text: String) {
        console.output(text.consoleText(), newLine: false)
    }

}
