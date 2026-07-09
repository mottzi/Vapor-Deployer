import Vapor
import Mist
import Elementary

protocol LogViewer: ManualComponent where FragmentState == Bool {
    
    static var componentName: String { get }
    static var streamName: String { get }
    static var consoleID: String { get }
    static var retainedLineCount: Int { get }
    
}

struct DeployerLogs: LogViewer {
    
    static let componentName = "DeployerLogs"
    static let streamName = "deployer-log"
    static let consoleID = "dp-deployer-log-console"
    static let retainedLineCount = 2000
    
}

struct TargetAppLogs: LogViewer {
    
    static let componentName = "TargetAppLogs"
    static let streamName = "app-log"
    static let consoleID = "dp-app-log-console"
    static let retainedLineCount = 2000
    
}

extension LogViewer {

    var name: String { Self.componentName }
    var state: LiveState<Bool> { LiveState(of: true) }
    var defaultState: ComponentState { ["wrapDisabled": .bool(true)] }
    var actions: [any Action] { [ToggleWrapAction()] }

    func body(state: Bool) -> some HTML {
        body(state: state, componentState: defaultState)
    }

    func body(state: Bool, componentState: ComponentState) -> some HTML {
        let wrapDisabled = componentState["wrapDisabled"]?.bool ?? false
        let consoleClass = wrapDisabled
            ? "dp-output-pre dp-output-pre--live dp-output-pre--nowrap dp-app-log-console"
            : "dp-output-pre dp-output-pre--live dp-app-log-console"

        return div(
            .class("dp-app-log-stream"),
            .mistComponent(name),
            .mistSSR(true)
        ) {
            pre(
                .id(Self.consoleID),
                .class(consoleClass),
                .mistStream(Self.streamName),
                .custom(name: "data-mist-stream-limit", value: "\(Self.retainedLineCount)")
            ) {}
        }
    }

}

struct ToggleWrapAction: Action {

    let name = "toggleWrap"

    func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {
        let wrapDisabled = state["wrapDisabled"]?.bool ?? false
        state["wrapDisabled"] = .bool(!wrapDisabled)
        return .success()
    }

}
