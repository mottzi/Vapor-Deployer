import Vapor

actor BuildOutputStream {

    private static let streamName = "build-output"
    private static let flushInterval: Duration = .milliseconds(100)
    private static let flushByteThreshold = 8 * 1024

    private let app: Application
    private let component: String
    private let modelID: UUID?

    private var pending = ""
    private var flushTask: Task<Void, Never>?

    init(app: Application, deployment: Deployment) {
        self.app = app
        self.component = RowComponent.name(for: deployment.product)
        self.modelID = deployment.id
    }

    func start() async {
        guard let modelID else { return }
        await app.mist.streams.replace(
            component: component,
            modelID: modelID,
            stream: Self.streamName,
            text: ""
        )
    }

    func append(_ text: String) async {
        guard !text.isEmpty else { return }
        pending.append(text)

        if pending.utf8.count >= Self.flushByteThreshold {
            await flush()
        } else {
            scheduleFlush()
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
