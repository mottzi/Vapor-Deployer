import Foundation
import Mist
import Vapor

actor DeployerLogTailer {

    private let app: Application
    private let logFilePath: String

    private var stream: StaticStream?
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    init(app: Application, logFilePath: String) {
        self.app = app
        self.logFilePath = logFilePath
    }

    func configure(stream: StaticStream) {
        self.stream = stream
    }

    func start() async {

        guard process == nil else { return }
        guard let stream else {
            app.logger.error("Deployer log tailer started before its Mist stream was configured.")
            return
        }

        await app.mist.streams.replace(stream, text: "")

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-n", "50", "-F", logFilePath]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.appendOutput(data) }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.recordTailError(data) }
        }

        process.terminationHandler = { [weak self, weak process] terminatedProcess in
            Task { await self?.finish(terminatedProcess, expectedProcess: process) }
        }

        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            self.outputPipe = nil
            self.errorPipe = nil
            app.logger.error("Failed to start deployer log tail for \(logFilePath): \(error.localizedDescription)")
            await app.mist.streams.append(stream, text: "Could not start log stream. Check the deployer log.\n")
        }
    }

    func stop() async {

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        outputPipe = nil
        errorPipe = nil

        if let stream {
            await app.mist.streams.close(stream)
        }
    }

}

private extension DeployerLogTailer {

    func appendOutput(_ data: Data) async {
        guard let stream else { return }

        let text = LogSanitizer.sanitize(String(decoding: data, as: UTF8.self))
        guard !text.isEmpty else { return }

        await app.mist.streams.append(stream, text: text)
    }

    func recordTailError(_ data: Data) {
        let text = LogSanitizer.sanitize(String(decoding: data, as: UTF8.self)).trimmed
        guard !text.isEmpty else { return }
        app.logger.debug("Deployer log tail stderr: \(text)")
    }

    func finish(_ terminatedProcess: Process, expectedProcess: Process?) async {

        guard expectedProcess == nil || terminatedProcess === expectedProcess else { return }
        guard process === terminatedProcess else { return }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }

}
