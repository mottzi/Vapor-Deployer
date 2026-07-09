## Unreleased changes main...HEAD(dev)

### Operator Interface & UX
- Add post-deployment health probes (supporting default TCP port checks and configurable HTTP GET path checks) with a 2-second settle check and automated rollback to the predecessor backup binary upon failure or timeout.
- Add an authenticated target app Logs page that streams the configured app log through Mist with subscriber-driven tailing, bounded 2000-line retention, local Clear/Copy actions, a per-client Wrap toggle, and viewport-filling console layout.
- Add `deployerctl` deployment controls: list deployments by short SHA, deploy, build, run saved binaries, test, inspect output, delete rows, and remove saved binaries.
- Display the commit SHA on all responsive size classes instead of only the desktop view.
- In the medium breakpoint, place the commit SHA in the right column underneath the build/binary details, and vertically center the row actions dropdown button.
- In the mobile breakpoint, position the commit SHA next to the row actions button to prevent layout wrapping, styling it to match adjacent metadata elements.
- Implement an interactive copy UX for commit SHAs: clicking copies the full SHA and animates the label to green "Copied" text for 2 seconds across all size classes.
- Add Deployer daemon service logs to the web panel, exposing the deployer's own `deployer.log` file at `/logs/deployer` with a dedicated Logs button in the status bar, generalized page templates, and improved logging timestamps.
- Add an emergency `--skip-health-check` flag to both `deployerctl deploy` and `deployerctl run` to bypass post-deployment health probes.
- Roll back self-updates when the newly started deployer fails post-start control-plane verification instead of accepting the first service-manager `running` status.
- Allow setup to reuse the existing webhook secret and skip GitHub token inputs if the repository identity and webhook URL are unchanged.
- Continue setup when the target app fails health checks, keeping Deployer health fatal while installing `deployerctl`, Nginx/TLS, and GitHub webhook support before reporting workload remediation commands.
- Preserve existing install mode, deployment mode, and testing defaults when rerunning setup, and clarify when `deployerBranch` is ignored on binary installs.
- Show automatic pushes waiting for the active deployment to finish as `queued` instead of the misleading `canceled` status.
- Add a `refresh-deployerctl` subcommand to `deployerctl` for manually updating the root-owned wrapper script.
- Refresh deployment rows after global operation locks clear so row action menus return automatically after reconnecting or loading the panel during a busy phase, and guard Mist's visibility wake-up ping against a socket that was already reset.
- Fix the deployer status badge cycling Ready→Updating→Ready multiple times when clicking the panel update button, caused by two phase publishers bypassing the centralized resolver and ignoring the updater sticky bit. Defer updater polling to after Mist component registration to prevent a startup-order crash on the freshly updated binary.
- Route self-update system logs to the shared `deployer.log` file without leaking them into the operator-facing CLI transcript, while still printing concise command failures to the operator and consistently treating already-live deploy/run requests as successful no-ops.
- Polish panel UI layouts: Standardized log viewer margins, console padding (16px 20px), and tablet font styles to match desktop; fixed status-bar log button styling; improved testing/built status color contrast; added a "Disconnected" websocket state badge; exposed the configured health check method in the target metadata strip; and defaulted the log viewer to disable line wrapping.

### System Mechanics
- Share one deployment engine between the panel and CLI, with cross-process operation locking so panel and CLI actions cannot run concurrently.
- Protect Panel Restart and Stop actions with the global deployment operation lock to prevent conflicting service state changes during active deployments.
- Persist operations and operation events in a local SQLite database to support status recovery and event streaming.
- Recover stranded/abandoned operations on server boot or CLI startup when the owning process no longer holds the operation lock, transitioning stuck deployments to `.failed` and purging temporary events.
- Stream CLI-origin deployment progress back into the live panel through Mist-backed operation events, while keeping CLI deploys usable when the server is offline.
- Refresh the root-owned `deployerctl` wrapper during successful self-updates by invoking the newly activated binary's embedded templates after the deployer service restarts.
- Install a narrow root helper and sudoers rule during setup/root refresh so panel-triggered updates from the service user can refresh only `/usr/local/sbin/deployerctl` and `/etc/deployer/deployerctl.conf`.
- Preserve existing deployerctl metadata while refreshing operational values from `deployer.json`, and keep existing installations safe by warning when a one-time root refresh is still needed to bootstrap the panel update helper.
- Route CLI-triggered framework and database system logs to the shared `deployer.log` file using a custom FileLogHandler, preventing them from leaking into the terminal's clean deployment transcript while maintaining full observability in the web panel log viewer.
- Persist setup toolchain paths in `deployer.json` so panel and CLI builds/tests use the same Swift environment.
- Persist the new deployer version marker before restarting during self-update, while restoring the previous marker on rollback so the panel metadata strip boots with the correct SHA.
- Refine binary retention behaviour parsing and validation rules, ensuring values are strictly positive.
- Log unauthorized access attempts to the `/control` route group with the client's IP address.

### Codebase Architecture
- Unify deployment-operation eligibility into one pure policy (`Deployment+OperationEligibility`) shared by panel presentation and engine enforcement, and split `OperationEngine+Pipeline` into promotion, build, test, maintenance, and pipeline-support files with a shared live-activation helper.
- Extract internal infrastructure into distinct, isolated domains (`Deployer/Host`, `Deployer/Shell`, `Deployer/GitHub`, `Deployer/Release`, `Deployer/Service`, `Deployer/Provisioning`, and `Deployer/BinaryStore`) to improve separation of concerns from application logic.
- Simplify operation and update lock APIs so callers no longer pass install directories, while sharing the underlying file-lock implementation between deployment mutations and self-updates.
- Add 27 high-value, non-spammy log statements across boot sequences, authentication audits, Panel UI actions, webhook execution, and setup/update CLI command steps, declaring loggers at the struct level as private properties to optimize performance and architecture.
- Refactor TargetAppLogs and DeployerLogs into a single generic FileLogTailer and LogViewer component to eliminate code duplication.
- Improve the semantic accuracy of the updater polling log, replacing a misleading timeout warning with an info message when the deployer successfully determines no update is needed and exits quickly.
- Split Panel and Application bootstrap routines into logical extensions to streamline route configuration, login handling, and asset registration.
- Update the `Vapor-Mist` dependency to the `dev` branch to support state-aware fragment rendering and component streaming.

### User-facing Changelog
- Add post-deployment health probes (supporting default TCP port checks and configurable HTTP GET path checks) with a 2-second settle check and automated rollback to the predecessor backup binary upon failure or timeout.
- Add an authenticated target app Logs page that streams the configured app log through Mist with subscriber-driven tailing, bounded 2000-line retention, local Clear/Copy/Wrap-lines actions.
- Add Deployer daemon service logs to the web panel, exposing the deployer's own `deployer.log` file at `/logs/deployer` with a dedicated Logs button in the status bar, generalized page templates, and improved logging timestamps.
- Add `deployerctl` CLI (deployment controls): list deployments by short SHA, deploy, build, run saved binaries, test, inspect output, delete rows, and remove saved binaries, largely mirroring the panel capabilities.
- Add an `--skip-health-check` flag to both `deployerctl deploy` and `deployerctl run` to bypass post-deployment health probes.
- Add a `refresh-deployerctl` subcommand to `deployerctl` for manually updating the root-owned wrapper script (internal use).
- Roll back self-updates when the newly started deployer fails post-start control-plane verification instead of accepting the first service-manager `running` status.
- Share one deployment engine between the panel and CLI, with cross-process operation locking so panel and CLI actions cannot run concurrently.
- Stream CLI-origin deployment progress back into the live panel through Mist-backed operation events, while keeping CLI deploys usable when the server is offline.
- Recover stranded/abandoned operations on server boot or CLI startup when the owning process no longer holds the operation lock, transitioning stuck deployments to `.failed` and purging temporary events.
- Display the commit SHA on all responsive size classes instead of only the desktop view.
- Polish panel UI layouts: added a "Disconnected" websocket state badge
- Refresh the root-owned `deployerctl` wrapper during successful self-updates by invoking the newly activated binary's embedded templates after the deployer service restarts.
