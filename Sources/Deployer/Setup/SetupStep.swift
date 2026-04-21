import Vapor

/// One phase in the setup pipeline that validates assumptions, mutates shared state, and provisions the host before the next phase.
protocol SetupStep {

    /// Short human label rendered in the `[i/n]` progress header so the operator can follow pipeline progress.
    var title: String { get }

    /// Shared mutable state carried across steps; each step reads prior inputs and may populate fields for later steps.
    var context: SetupContext { get }

    /// Interactive console used for prompts, progress output, and warnings during the setup run.
    var console: any Console { get }

    /// Dependency-injected initializer so `SetupCommand` can assemble every step against one shared context and console.
    init(context: SetupContext, console: any Console)

    /// Executes this step's work; may prompt, shell out, and mutate `context`, and must throw on unrecoverable failure.
    func run() async throws

}

extension SetupStep {

    /// Convenience accessor for a `SetupShell` bound to this step's context, used for service-user shell commands.
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
