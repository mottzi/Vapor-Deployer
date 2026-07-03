import Mist
import Elementary

struct TargetAppLogs: ManualComponent {

    static let componentName = "TargetAppLogs"
    static let streamName = "app-log"
    static let retainedLineCount = 1000

    let name = TargetAppLogs.componentName
    let state = LiveState(of: true)
    let actions: [Action] = []

    func body(state: Bool) -> some HTML {
        div(.mistComponent(name), .mistSSR(true)) {}
    }

}
