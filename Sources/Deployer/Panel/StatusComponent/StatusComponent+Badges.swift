import Elementary

extension StatusComponent {

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
        span(.class("dp-supervisor-badge dp-supervisor-badge--running")) {
            "running"
        }
    }

    var fatalBadge: some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--fatal")) {
            "fatal"
        }
    }

    func transitioningBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--transitioning")) {
            status
        }
    }

    func stoppedBadge(_ status: String) -> some HTML {
        span(.class("dp-supervisor-badge dp-supervisor-badge--stopped")) {
            status
        }
    }

}
