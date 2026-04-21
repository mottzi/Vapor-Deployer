import Vapor

/// One phase in the setup pipeline that validates assumptions, mutates shared state, and provisions the host before the next phase.
protocol SetupStep {

    var title: String { get }
    
    var context: SetupContext { get }
    
    var console: any Console { get }

    init(context: SetupContext, console: any Console)

    func run() async throws

}

extension SetupStep {

    var shell: SetupShell { SetupShell(context: context) }

    /// Prints a consistent progress header so interactive setup output stays scannable across steps.
    func printHeader(index: Int, total: Int) {
        self.console.titledRule("[\(index)/\(total)] \(title)")
    }

}
