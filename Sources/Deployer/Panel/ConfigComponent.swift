import Vapor
import Mist
import Elementary

struct ConfigComponent: ManualComponent {

    var name: String
    let state: LiveState<ConfigState>

    func body(state: ConfigState) -> some HTML {
        div(
            .class("dp-config-card"),
            .mistComponent(value: state.componentName)
        ) {
            for group in state.groups {
                section(.class("dp-config-group")) {
                    h3(.class("dp-config-group-title")) { group.title }
                    dl(.class("dp-config-grid")) {
                        for field in group.fields {
                            dt(.class("dp-config-label")) { field.label }
                            dd(.class("dp-config-value")) { field.value }
                        }
                    }
                }
            }
        }
    }
    
    init(using config: DeployerConfiguration) {
        self.name = "ConfigComponent-\(config.target.name)"
        self.state = LiveState(of: ConfigState(config: config, componentName: self.name))
    }

}

struct ConfigState: ComponentData {

    let componentName: String
    let groups: [Group]

    init(
        config: DeployerConfiguration,
        componentName: String
    ) {
        self.componentName = componentName

        let targetFields = [
            Field("Name", config.target.name),
            Field("Directory", config.target.directory),
            Field("Build Mode", config.target.buildMode),
            Field("Deploy Mode", config.target.deploymentMode.rawValue),
            Field("Push Event", config.target.pusheventPath.displayPath)
        ]

        let deployerPanelFields = [
            Field("Port", String(config.port)),
            Field("DB File", config.dbFile),
            Field("Mist Socket", config.socketPath.displayPath),
            Field("Panel Route", config.panelRoute.displayPath)
        ]

        self.groups = [
            Group("Panel", deployerPanelFields),
            Group("Target", targetFields)
        ]
    }

}

extension ConfigState {

    struct Group: ComponentData {

        let title: String
        let fields: [Field]

        init(_ title: String, _ fields: [Field]) {
            self.title = title
            self.fields = fields
        }

    }

    struct Field: ComponentData {

        let label: String
        let value: String

        init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

}

private extension String {

    var displayPath: String {
        let segments = self.pathComponents.map(\.description)
        guard !segments.isEmpty else { return "/" }
        return "/" + segments.joined(separator: "/")
    }

}
