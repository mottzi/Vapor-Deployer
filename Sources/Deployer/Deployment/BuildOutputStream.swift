import Vapor

actor BuildOutputStream {

    private static let streamName = "deployment-log"
    private static let flushInterval: Duration = .milliseconds(100)
    private static let flushByteThreshold = 8 * 1024

    private let app: Application
    private let component: String
    private let modelID: UUID?

    private(set) var transcript = ""
    private var pending = ""
    private var flushTask: Task<Void, Never>?

    init(app: Application, deployment: Deployment, priorTranscript: String = "") {
        self.app = app
        self.component = DeploymentRow.name(for: deployment.product)
        self.modelID = deployment.id
        self.transcript = priorTranscript
    }

    /// Replaces the live panel view with the seed transcript so a manual test run on a row with
    /// prior `output` shows that history immediately and appends the new section beneath it.
    func start() async {
        guard let modelID else { return }
        await app.mist.streams.replace(
            component: component,
            modelID: modelID,
            stream: Self.streamName,
            text: transcript
        )
    }

    func append(_ text: String) async {
        guard !text.isEmpty else { return }
        let cleaned = Self.stripAnsi(text)
        guard !cleaned.isEmpty else { return }
        transcript.append(cleaned)
        pending.append(cleaned)

        if pending.utf8.count >= Self.flushByteThreshold {
            await flush()
        } else {
            scheduleFlush()
        }
    }

    /// Strips ANSI escape sequences (color codes, cursor moves) so the log renders cleanly in a browser `<pre>`.
    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[a-zA-Z]")

    private static func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
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

    func flush() async {
        flushTask?.cancel()
        flushTask = nil

        guard !pending.isEmpty else { return }
        guard let modelID else { return }

        let chunk = pending
        pending = ""

        await app.mist.streams.append(
            component: component,
            modelID: modelID,
            stream: Self.streamName,
            text: chunk
        )
    }

    func close() async {
        await flush()

        guard let modelID else { return }

        await app.mist.streams.close(
            component: component,
            modelID: modelID,
            stream: Self.streamName
        )
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }

        flushTask = Task {
            try? await Task.sleep(for: Self.flushInterval)
            await self.flush()
        }
    }

}
