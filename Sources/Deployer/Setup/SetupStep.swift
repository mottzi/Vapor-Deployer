import Vapor

/// One phase in the setup pipeline that validates assumptions, mutates shared state, and provisions the host before the next phase.
protocol SetupStep {

    ///
    var title: String { get }
    
    ///
    var context: SetupContext { get }
    
    ///
    var console: any Console { get }

    ///
    init(context: SetupContext, console: any Console)

    ///
    func run() async throws

}

extension SetupStep {

    ///
    var shell: SetupShell { SetupShell(context: context) }

    /// Non-optional view of the derived path layout, trusting `InputStep` to have populated it first in the pipeline.
    var paths: SetupPaths {
        guard let paths = context.paths else {
            preconditionFailure("SetupStep.paths accessed before InputStep populated SetupContext.paths — check step ordering in SetupCommand.run")
        }
        return paths
    }

    /// Prints a consistent progress header so interactive setup output stays scannable across steps.
    func printHeader(index: Int, total: Int) {
        console.titledRule("[\(index)/\(total)] \(title)")
    }

}
