import Vapor
import Mist
import Elementary

struct DeployerInfoComponent: ManualComponent {

    var name: String
    let state: LiveState<DeployerInfoState>

    func body(state: DeployerInfoState) -> some HTML {
        div(
            .style("display: contents;"),
            .mistComponent(state.componentName)
        ) {
            for field in state.fields {
                div(.class(Self.contextItemClass(for: field))) {
                    span(.class("dp-context-label")) { field.label }
                    span(.class("dp-context-value"), .title(field.value)) { field.value }
                }
            }
        }
    }

    private static func contextItemClass(for field: DeployerInfoState.Field) -> String {
        let base = "dp-context-item"
        return switch field.label {
            case "Port":      "\(base) dp-context-item--port"
            case "Directory": "\(base) dp-context-item--deployerdir"
            case "Version":   "\(base) dp-context-item--version"
            case "Socket":    "\(base) dp-context-item--socket"
            default: base
        }
    }

    init(using config: Configuration, version: String) {
        self.name = "DeployerInfoComponent"
        self.state = LiveState(
            of: DeployerInfoState(config: config, version: version, componentName: self.name)
        )
    }

}

struct DeployerInfoState: ComponentData {

    let componentName: String
    let fields: [Field]

    init(config: Configuration, version: String, componentName: String) {
        self.componentName = componentName

        var fields: [Field] = [
            Field("Port", String(config.port)),
            Field("Directory", config.deployerDirectory),
            Field("Version", version)
        ]

        if config.deployerBranch != "main" {
            fields.append(Field("Branch", config.deployerBranch))
        }

        fields.append(contentsOf: [
            Field("Service Manager", config.serviceManager.rawValue),
            Field("User", UserAccount.currentName() ?? ""),
            Field("Build from Source", config.buildFromSource ? "yes" : "no"),
            Field("Socket", config.socketPath.displayPath)
        ])

        self.fields = fields
    }

}

extension DeployerInfoState {

    struct Field: ComponentData {

        let label: String
        let value: String

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

}
