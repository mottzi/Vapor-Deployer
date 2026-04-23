import Vapor

/// One phase in the update pipeline that validates assumptions, mutates shared state, and provisions the host before the next phase.
protocol UpdateStep {

    /// Short human label rendered in the `[i/n]` progress header so the operator can follow pipeline progress.
    var title: String { get }

    /// Shared mutable state carried across steps; each step reads prior inputs and may populate fields for later steps.
    var context: UpdateContext { get }

    /// Interactive console used for prompts, progress output, and warnings during the update run.
    var console: any Console { get }

    /// Dependency-injected initializer so `UpdateCommand` can assemble every step against one shared context and console.
    init(context: UpdateContext, console: any Console)

    /// Executes this step's work; may prompt, shell out, and mutate `context`, and must throw on unrecoverable failure.
    func run() async throws

}

extension UpdateStep {

    /// Convenience accessor for a `SystemShell` bound to this step's context, used for service-user shell commands.
    var shell: SystemShell { SystemShell(context: context) }

    /// Prints a yellow-accented progress header to visually distinguish update output from setup and remove output.
    func printHeader(index: Int, total: Int) {
        console.updateTitledRule("[\(index)/\(total)] \(title)")
    }

}

extension Console {

    func updateBanner() {
        self.output("")
        self.output(Self.rule().consoleText(color: .yellow))
        self.output("  Vapor Deployer · Update".consoleText(color: .yellow, isBold: true))
        self.output(Self.rule().consoleText(color: .yellow))
        self.output("")
        self.output("  Downloads and installs the latest version of the deployer.".consoleText())
        self.output("  Automatically restarts the service after staging new assets.".consoleText())
        self.output("")
    }

    func updateTitledRule(_ title: String) {
        self.output("")
        self.output(Self.titledRuleText(title).consoleText(color: .yellow, isBold: true))
    }

}
