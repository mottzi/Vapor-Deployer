import Mist

struct TargetStatusBroadcaster: Sendable {
    
    let badge: LiveState<StatusState>
    let actions: LiveState<StatusState>

    func set(_ state: StatusState) async {
        await badge.set(state)
        await actions.set(state)
    }

    func setBadge(_ state: StatusState) async {
        await badge.set(state)
    }
    
}
