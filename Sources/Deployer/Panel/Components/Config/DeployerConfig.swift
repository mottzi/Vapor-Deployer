import Vapor
import Mist
import Elementary

struct DeployerConfig: ManualComponent {

    var name: String
    let state: LiveState<DeployerInfoState>

    func body(state: DeployerInfoState) -> some HTML {
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

    init(using config: Configuration, version: String) {
        self.name = "DeployerConfig"
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

        self.fields = [
            Field("Port", String(config.port)),
            Field("Directory", config.deployerDirectory.displayPath),
            Field("Branch", config.deployerBranch),
            Field("Version", version),
            Field("User", UserAccount.currentName() ?? ""),
            Field("Service", config.serviceBackend.rawValue),
            Field("Installation", config.buildFromSource ? "local build" : "release"),
            Field("Socket", config.socketPath.displayPath),
        ]
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
