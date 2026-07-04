import Mist
import Elementary

struct TargetAppLogs: ManualComponent {

    static let componentName = "TargetAppLogs"
    static let streamName = "app-log"
    static let retainedLineCount = 2000

    let name = TargetAppLogs.componentName
    let state = LiveState(of: true)
    let actions: [Action] = []

    func body(state: Bool) -> some HTML {
        div(
            .class("dp-app-log-stream"),
            .mistComponent(name),
            .mistSSR(true)
        ) {
            pre(
                .id("dp-app-log-console"),
                .class("dp-output-pre dp-output-pre--live dp-app-log-console"),
                .mistStream(Self.streamName),
                .custom(name: "data-mist-stream-limit", value: "\(Self.retainedLineCount)")
            ) {}
        }
    }

}
