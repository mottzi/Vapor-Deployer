import Vapor

/// One phase in the remove pipeline that tears down a resource, using best-effort where appropriate.
protocol RemoveStep {

    /// Short human label rendered in the `[i/n]` progress header so the operator can follow pipeline progress.
    var title: String { get }

    /// Shared mutable state for the remove run; each step reads collected inputs and discovered metadata.
    var context: RemoveContext { get }

    /// Interactive console used for prompts, progress output, and warnings during the remove run.
    var console: any Console { get }

    /// Dependency-injected initializer so `RemoveCommand` can assemble every step against one shared context and console.
    init(context: RemoveContext, console: any Console)

    /// Executes this step's work; may prompt, shell out, and must throw only on unrecoverable failure.
    func run() async throws

}

extension RemoveStep {

    /// Convenience accessor for a `SystemShell` bound to this step's context, used for service-user shell commands.
    var shell: SystemShell { SystemShell(context: context) }

    /// Non-optional view of the derived path layout, trusting `RemoveInputStep` to have populated it first in the pipeline.
    var paths: SystemPaths {
        guard let paths = context.paths else {
            preconditionFailure("RemoveStep.paths accessed before RemoveInputStep populated RemoveContext.paths")
        }
        return paths
    }

    /// Executes a closure, logging a warning on failure instead of halting the pipeline.
    func bestEffort(_ label: String, _ body: () async throws -> Void) async {
        do { try await body() }
        catch { console.warning("\(label): \(error)") }
    }

}
