import Vapor
import Mist
import Elementary

struct ConfigComponent: ManualComponent {

    var name: String
    let state: LiveState<ConfigState>

    func body(state: ConfigState) -> some HTML {
        div(
            .style("display: contents;"),
            .mistComponent(value: state.componentName)
        ) {
            for field in state.fields {
                div(.class(Self.contextItemClass(for: field))) {
                    span(.class("dp-context-label")) { field.label }
                    span(
                        .class("dp-context-value"),
                        .title(field.value)
                    ) { field.value }
                }
            }
        }
    }

    private static func contextItemClass(for field: ConfigState.Field) -> String {
        let base = "dp-context-item"
        switch field.label {
        case "Port": return "\(base) dp-context-item--target-port"
        case "Directory": return "\(base) dp-context-item--target-directory"
        default: return base
        }
    }

    init(using config: Configuration) {
        self.name = "ConfigComponent-\(config.target.name)"
        self.state = LiveState(
            of: ConfigState(config: config, componentName: self.name)
        )
    }

}

struct ConfigState: ComponentData {

    let componentName: String
    let fields: [Field]

    init(config: Configuration, componentName: String) {
        self.componentName = componentName
        self.fields = [
            Field("Port", String(config.target.appPort)),
            Field("Directory", config.target.directory),
            Field("Build Mode", config.target.buildMode),
            Field("Deploy Mode", config.target.deploymentMode.rawValue),
            Field("Push Event", config.target.pusheventPath.displayPath)
        ]
    }

}

extension ConfigState {

    struct Field: ComponentData {

        let label: String
        let value: String

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

}
