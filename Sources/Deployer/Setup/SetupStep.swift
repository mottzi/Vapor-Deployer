import Vapor

protocol SetupStep: Sendable {

    var title: String { get }

    func run(context: SetupContext, console: any Console) async throws

}

extension SetupStep {

    func printHeader(index: Int, total: Int, console: any Console) {
        SetupCards.titledRule("[\(index)/\(total)] \(title)", console: console)
    }

}
