import Vapor
import Mist

extension TargetAppLogs {

    struct ToggleWrapAction: Action {

        let name = "toggleWrap"

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            let wrapDisabled = state["wrapDisabled"]?.bool ?? false
            state["wrapDisabled"] = .bool(!wrapDisabled)

            return .success()
        }

    }

}
