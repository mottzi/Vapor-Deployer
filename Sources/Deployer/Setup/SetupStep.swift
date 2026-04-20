import Vapor

/// One phase in the setup pipeline that validates assumptions, mutates shared state, and provisions the host before the next phase.
protocol SetupStep: Sendable {

    var title: String { get }

    func run(context: SetupContext, console: any Console) async throws

}

extension SetupStep {

    /// Prints a consistent progress header so interactive setup output stays scannable across steps.
    func printHeader(index: Int, total: Int, console: any Console) {
        console.titledRule("[\(index)/\(total)] \(title)")
    }

}
