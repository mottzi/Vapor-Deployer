import Vapor
import Mist
import Elementary

struct DeployerLogs: ClientStateManualComponent {

    static let componentName = "DeployerLogs"
    static let streamName = "deployer-log"
    static let retainedLineCount = 2000

    let name = DeployerLogs.componentName
    let state = LiveState(of: true)
    let defaultState: ComponentState = ["wrapDisabled": .bool(false)]
    let actions: [any Action] = [ToggleWrapAction()]

    func body(state: Bool) -> some HTML {
        body(state: state, clientState: defaultState)
    }

    func body(state: Bool, clientState: ComponentState) -> some HTML {
        let wrapDisabled = clientState["wrapDisabled"]?.bool ?? false
        let consoleClass = wrapDisabled
            ? "dp-output-pre dp-output-pre--live dp-output-pre--nowrap dp-app-log-console"
            : "dp-output-pre dp-output-pre--live dp-app-log-console"

        return div(
            .class("dp-app-log-stream"),
            .mistComponent(name),
            .mistSSR(true)
        ) {
            pre(
                .id("dp-deployer-log-console"),
                .class(consoleClass),
                .mistStream(Self.streamName),
                .custom(name: "data-mist-stream-limit", value: "\(Self.retainedLineCount)")
            ) {}
        }
    }

    func renderClientState(app: Application, state componentState: ComponentState) async -> RenderResult {
        let current = await state.current
        return .rendered(body(state: current, clientState: componentState).render())
    }

}
