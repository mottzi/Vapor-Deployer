import Vapor
import Mist
import Elementary

struct TargetConfig: ManualComponent {

    var name: String
    let state: LiveState<TargetInfoState>

    func body(state: TargetInfoState) -> some HTML {
        div(
            .style("display: contents;"),
            .mistComponent(state.componentName)
        ) {
            for field in state.fields {
                div(.class("dp-context-item")) {
                    span(.class("dp-context-label")) { field.label }
                    span(.class("dp-context-value"), .title(field.value)) { field.value }
                }
            }
        }
    }

    init(using config: Configuration) {
        self.name = "TargetConfig-\(config.target.name)"
        self.state = LiveState(
            of: TargetInfoState(config: config, componentName: self.name)
        )
    }

}

struct TargetInfoState: ComponentData {

    let componentName: String
    let fields: [Field]

    init(config: Configuration, componentName: String) {
        self.componentName = componentName
        self.fields = [
            Field("Port", String(config.target.appPort)),
            Field("Directory", config.target.directory.displayPath),
            Field("Branch", config.target.branch),
            Field("Build Mode", config.target.buildMode),
            Field("Deploy Mode", config.target.deploymentMode.rawValue),
            Field("Binary Retention", config.target.binaryBehaviour.setupValue),
            Field("Push Event", config.target.pusheventPath.displayPath)
        ]
    }

}

extension TargetInfoState {

    struct Field: ComponentData {

        let label: String
        let value: String

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

}
