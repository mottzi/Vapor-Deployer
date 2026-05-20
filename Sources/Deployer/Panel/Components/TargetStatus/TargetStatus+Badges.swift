import Elementary

extension TargetStatus {

    @HTMLBuilder
    func statusBadge(of state: StatusState) -> some HTML {

        switch (state.isTransitioning, state.isRunning, state.status) {
            case (true, _, let status): transitioningBadge(status)
            case (false, true, _): runningBadge
            case (false, false, "fatal"): fatalBadge
            case (false, false, let status): stoppedBadge(status)
        }
    }

    var runningBadge: some HTML {
        span(.class("dp-state-badge dp-state-badge--running")) {
            "running"
        }
    }

    var fatalBadge: some HTML {
        span(.class("dp-state-badge dp-state-badge--fatal")) {
            "fatal"
        }
    }

    func transitioningBadge(_ status: String) -> some HTML {
        span(.class("dp-state-badge dp-state-badge--transitioning")) {
            status
        }
    }

    func stoppedBadge(_ status: String) -> some HTML {
        span(.class("dp-state-badge dp-state-badge--stopped")) {
            status
        }
    }

}
