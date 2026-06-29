# CLI Deploy Recovery Control Surface Implementation Plan

## Summary

This feature adds a production-grade deployment CLI for Vapor-Deployer. The goal is to make deployment-row operations available from `deployerctl` with the same domain behavior as the browser panel, while preserving a critical recovery property: CLI deploys must work even when the server and panel are offline.

The CLI and panel must not become two separate deployment systems. They should share one deployment engine, one operation lock, one crash-recovery model, and one event/output pipeline. When the server is online, CLI-origin deploys must live-update the panel through Mist, including build/test logs. When the server is offline, CLI-origin deploys must still run to completion and leave durable database state for the panel to show later.

This plan implements ADR 0009, "CLI deploy is a recovery control surface", and the glossary terms in `CONTEXT.md`: Deployment selector, Recovery deploy, Operator deployment, Automatic deployment, Operation lock, Operation event stream, and Abandoned operation.

## Non-Negotiable Behavior

- CLI deploy commands work when the Deployer server/panel is offline.
- Panel and CLI deployment operations share the same underlying deployment engine.
- No mutating panel path may run concurrently with a mutating CLI path, and vice versa.
- The cross-process mutex is `<installDir>/.deployer-operation.lock`.
- Read-only commands may run while the operation lock is held.
- CLI-origin operations live-update the online panel through Mist via a durable operation event stream.
- The server can attach to an already-running CLI operation after server start/restart.
- Panel and CLI operations use the same abandoned-operation recovery rule.
- Human-facing deployment identifiers are short Git SHAs in both panel and CLI.
- Deployment UUIDs remain internal identifiers for Mist, database persistence, and diagnostics.
- Environment-variable CLI support is out of scope for this feature.
- No `--json`, no `--detach`, and no `--no-color` in v1.

## Command Surface

Register these top-level commands in `Deployer.useCommands()`:

```text
deployerctl deploy
deployerctl deploy <sha> [--testing] [--skip-tests --yes] [--no-logs]
deployerctl build <sha> [--no-logs]
deployerctl run <sha>
deployerctl test <sha> [--no-logs]
deployerctl output <sha>
deployerctl delete <sha> [--yes]
deployerctl remove-binary <sha> [--yes]
```

Behavior:

- `deploy` with no arguments lists the same newest-first deployment rows as the panel, defaulting to 20 rows. Do not include a target summary header; users can use `config` for configuration.
- `deploy <sha>` promotes exactly that selected commit. It does not drain queued webhook pushes.
- `build <sha>` builds and saves a binary without making it live.
- `run <sha>` restores and runs a saved binary.
- `test <sha>` runs the manual test audit and never changes deployment lifecycle status except transiently while testing.
- `output <sha>` prints stored output or follows live CLI-origin output until completion. It does not follow panel-started operations live.
- `delete <sha>` deletes a deployment row. It refuses the live deployment and prompts unless `--yes`.
- `remove-binary <sha>` removes a saved binary, resets the row to `pushed`, and prompts unless `--yes`.
- Mutating commands wait until completion.
- Mutating commands stream logs to the terminal by default when logs exist.
- `--no-logs` suppresses CLI log rendering only. The operation still writes events so the panel can stream logs.

Exit behavior:

- Successful completion exits `0`.
- Promoting an already-live deployment exits `0` with "already live" and makes no change.
- Parse/usage failures exit as ConsoleKit normally does for command errors.
- Busy operation lock, ambiguous SHA, missing deployment, missing binary, and failed build/test/deploy should return non-zero errors with concise human messages.

## Deployment Selection Rules

Use Git commit SHA as the operator selector.

- Accept full SHAs and unambiguous SHA prefixes.
- Reject ambiguous prefixes and show the matching short SHAs plus commit messages.
- Do not accept deployment UUIDs as normal CLI selectors.
- Known deployment rows may be selected by SHA/prefix.
- Unknown SHAs are allowed only when they can be resolved from the configured branch:
  - Fetch the configured origin/branch.
  - Verify the SHA is reachable from the configured branch.
  - If reachable, create a `Deployment` row automatically and continue.
  - If not reachable, refuse.

The created unknown-SHA row should match a webhook-created row as closely as possible:

- `product = target.name`
- `status = .pushed` before operation start
- `commitID = resolved full SHA`
- `branch = configured target branch`
- `commitMessage = git commit subject`
- `createdAt` from the database timestamp behavior
- `startedAt` set only when the operation actually starts, following existing queue semantics

## Operation Lock

Add an `OperationLock` type modeled after `UpdateLock`.

Requirements:

- Lock file: `<installDir>/.deployer-operation.lock`.
- Uses `flock(2)`.
- Non-blocking acquire for mutating operations.
- Non-destructive `isHeld()` peek for server status and UI disabling.
- Kernel-released on process exit, including crash/kill.
- File should be created with permissive enough mode for the configured runtime user/root wrapper pattern, matching the spirit of `UpdateLock`.

All mutating operations must acquire this lock:

- `deploy <sha>`
- `build <sha>`
- `run <sha>`
- `test <sha>`
- `delete <sha>`
- `remove-binary <sha>`
- panel deployment row actions
- panel target stop/restart actions
- self-update

Read-only operations do not acquire it:

- `deploy` list
- `output <sha>` when only reading existing output
- status/config/service-log wrapper commands that do not mutate deployment rows

Update integration:

- `UpdateCommand` should acquire `OperationLock` in addition to `UpdateLock`.
- Preserve `UpdateLock` for update-specific phase detection and existing ADR 0005 behavior.
- Acquire locks in one fixed order everywhere to avoid deadlock. Recommended order for update: `OperationLock` first, then `UpdateLock`.

Panel integration:

- Runtime badge shows `deploying` if the Operation lock is held and Update lock is not held.
- Panel actions are disabled while the Operation lock is held.
- Every panel action still attempts lock acquisition when starting; failure returns the same style of "operation already running" message as current queue-busy failures.

## Operation Event Stream

Add durable operation-event storage in SQLite.

Suggested Fluent models:

```swift
final class Operation: Model {
    static let schema = "operations"

    @ID var id: UUID?
    @Field var kind: Kind
    @Field var origin: Origin
    @Field var product: String
    @OptionalField var deploymentID: UUID?
    @Field var status: Status
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @OptionalField var startedAt: Date?
    @OptionalField var finishedAt: Date?
}

final class OperationEvent: Model {
    static let schema = "operation_events"

    @ID var id: UUID?
    @Field var operationID: UUID
    @Field var sequence: Int
    @Field var type: EventType
    @OptionalField var deploymentID: UUID?
    @OptionalField var payload: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
}
```

Keep the actual implementation idiomatic for the codebase; the field list above is the intended minimum shape, not mandatory syntax.

Operation statuses:

- `running`
- `completed`
- `failed`

Operation origins:

- `server`
- `cli`

Operation kinds:

- `deploy`
- `build`
- `run`
- `test`
- `delete`
- `removeBinary`
- `update`
- `targetStop`
- `targetRestart`

Event types:

- `started`
- `row-updated`
- `row-deleted`
- `log-appended`
- `service-status`
- `completed`
- `failed`

Event rules:

- Store stripped plain-text logs only.
- Do not preserve ANSI output in v1.
- Use monotonic per-operation sequence numbers so consumers can poll after the last seen event.
- Persist final deployment transcript to `Deployment.output` at operation completion, as current code does.
- Delete operation/event rows once the deployment reaches a terminal state and final output has been persisted.

Server event consumer:

- On server boot, find running CLI-origin operations.
- If Operation lock is held, attach to the newest/open active operation.
- Poll new operation events by sequence.
- On `row-updated`, re-render affected `DeploymentRow` through Mist.
- On `row-deleted`, remove the affected `DeploymentRow` through Mist.
- On `log-appended`, append to `app.mist.streams`.
- On initial attach, seed Mist stream from existing operation events using `replace`.
- On completion/failure, close the Mist stream.
- Keep this bridge server-side; CLI never talks directly to browser clients.
- Do not consume server-origin operations; they stream directly through in-process Mist sinks.

## Shared Deployment Engine

Extract deployment execution from `Queue+Execution` into a reusable service, tentatively `DeploymentEngine`.

The engine owns:

- action guards
- Operation lock acquisition for mutating operations
- Operation row/event creation
- transient status changes
- worker orchestration
- service restart/status updates
- final transcript persistence
- operation event cleanup
- abandoned-operation repair

Inputs:

- `Application` or a smaller runtime context containing database, thread pool/event loop, service manager, configuration, and event sink.
- Target configuration.
- Deployment row.
- Operation mode.
- Per-job test policy.
- Output policy for CLI rendering.

Operation modes:

- promote
- build
- runSavedBinary
- test
- delete
- removeBinary

Test policy:

- configured
- force enabled
- force disabled

Output/event flow:

- Replace `BuildOutputStream` as a hard dependency of `Worker`.
- Introduce an engine-neutral output sink that:
  - strips ANSI
  - accumulates transcript
  - writes `OperationEvent.log-appended` for CLI-origin operations
  - writes directly to Mist for server-origin operations
  - optionally writes to CLI console
- Mist output for server-origin operations is direct. Mist output for CLI-origin operations is produced by the server event consumer.

Worker:

- Keep `Worker` responsible for concrete shell/service/file operations.
- Adapt `Worker` to accept the new output sink instead of `BuildOutputStream?`.
- Preserve current labels:
  - `git fetch origin <branch>`
  - `git checkout --detach -f <short-sha>`
  - `swift test -c <buildMode>`
  - `swift build -c <buildMode>`
  - `deployer`
- Preserve `.build-tests` scratch path for tests.

Promotion behavior:

- If selected deployment is live: no-op success.
- If selected deployment has a saved binary: restore/run it.
- If selected deployment has no saved binary: checkout, optional inline test, build, install live binary, restart service, archive live binary, set current, evict according to `BinaryStore`.
- `deploy <sha> --testing` on saved-binary deployment refuses; do not implement test-gated restore in v1.
- `deploy <sha> --skip-tests --yes` skips inline tests for this job only.

Operator vs automatic behavior:

- Add a queue policy concept internally even if not persisted:
  - operator: exact selected commit
  - automatic: drain newer canceled pushes
- Panel manual `Build & Run` and CLI `deploy <sha>` use operator behavior.
- Webhook automatic deployment and boot drain keep current newest-eligible-push behavior.

## Headless CLI Runtime

Do not call `useServer()` for CLI deploy commands.

Add a headless setup path that:

- loads `Configuration`
- creates DB directory
- configures Fluent SQLite
- registers deployment binary cleanup middleware
- registers `Deployment`, `Operation`, and `OperationEvent` migrations
- runs auto-migrate
- initializes `ServiceManager`
- initializes deployment engine/services
- runs abandoned-operation repair

Do not require:

- `GITHUB_WEBHOOK_SECRET`
- `PANEL_PASSWORD_HASH`
- HTTP server configuration
- Leaf views
- sessions
- Mist socket
- webhook routes
- panel routes
- control routes

The headless runtime must use the configured service user for target-app work.

## Privilege And `deployerctl` Wrapper

Current target-app deployments run inside the server process. The systemd and supervisor templates both run that server as the configured service user. The CLI deployment path must match that ownership model.

Update `DeployerctlTemplate`:

- Add the deployment commands to usage:
  - `deploy`
  - `build`
  - `run`
  - `test`
  - `output`
  - `delete`
  - `remove-binary`
- Continue requiring root for wrapper-managed operational commands.
- For deployment commands, source `/etc/deployer/deployerctl.conf`, resolve service identity, resolve installed binary, and execute the Swift command as the configured service user.
- Keep `update`, `setup`, `remove`, `config`, `version`, and existing service-control commands behavior unchanged.
- Do not put systemd/supervisor branching in CLI command implementations; use the existing `ServiceManager`.

Systemd note:

- When wrapper re-execs as service user for commands that may call `systemctl --user`, preserve the `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` environment just like existing wrapper helpers.

Supervisor note:

- Supervisor service control currently shells out to `supervisorctl`.
- Do not redesign supervisor permissions in this feature.
- If service-user execution cannot call `supervisorctl` in an installation, treat it as an implementation bug to resolve in the service manager/wrapper integration, not by duplicating service-manager logic in CLI commands.

## Panel Changes

Deployment row display:

- Change the main table column from `ID` to `SHA`.
- Show short commit SHA everywhere in the panel table.
- Copy button copies full commit SHA.
- Keep UUID as `mist-id`.
- Keep UUID available only internally/diagnostically.

Presentation:

- Add computed properties to `Deployment+Presentation`:
  - `shortSHA`
  - `fullSHA`
- Stop using `shortID` in visible table content once the row template is updated.

Panel actions:

- Refactor `DeployAction`, `SaveBinaryAction`, `RestoreBinaryAction`, `TestAction`, `RemoveBinaryAction`, and `DeleteAction` to call the shared deployment operation service.
- Preserve current labels and messages where possible.
- Preserve current panel parity:
  - Build is only available without saved binary.
  - Run is only available with saved binary.
  - Test is allowed on live deployments.
  - Delete refuses live deployment.
  - Remove binary resets to `pushed`.

Target stop/restart:

- Include target stop/restart in Operation lock protection.
- Emit service-status events where useful so the badge behavior remains consistent.

## Queue Changes

Keep `Queue` as the server-process coordinator for webhook/panel entrypoints, but it must no longer be the cross-process source of truth.

Refactor:

- `Queue.start` should acquire the Operation lock through the shared engine for mutating work.
- `Queue.isDeploying` remains useful for in-process panel/webhook state but not sufficient for global mutual exclusion.
- `Queue.runQueue` should be split so automatic drain behavior is explicit and not reused for operator actions.
- `drainOnBoot()` keeps automatic behavior.
- Manual panel deploy uses exact selected commit behavior.

## Migrations

Existing migrations live in `Deployment.migrations`.

Add migrations for:

- `operations`
- `operation_events`

Register them anywhere `configureDatabase` and headless runtime configure the database.

Because this project already uses auto-migrate, no separate migration command is needed.

Indexes to add if Fluent supports them cleanly:

- `operations.status`
- `operations.deployment_id`
- `operation_events.operation_id`
- `operation_events.sequence`

If index support is awkward, do not block v1; the event volume is small and local.

## Command Implementation Notes

ConsoleKit signatures can be awkward for "no args means list, one arg means action". Prefer `AnyAsyncCommand` with manual argument parsing if it keeps the code simpler and matches `ConfigCommand` style.

Suggested command grouping:

- `Sources/Deployer/Commands/Deploy/DeployCommand.swift`
- `Sources/Deployer/Commands/Deploy/BuildCommand.swift`
- `Sources/Deployer/Commands/Deploy/RunCommand.swift`
- `Sources/Deployer/Commands/Deploy/TestCommand.swift`
- `Sources/Deployer/Commands/Deploy/OutputCommand.swift`
- `Sources/Deployer/Commands/Deploy/DeleteCommand.swift`
- `Sources/Deployer/Commands/Deploy/RemoveBinaryCommand.swift`
- Shared parser/table/renderer helpers in the same folder.

Listing table:

- Columns should be compact and operator-focused:
  - live marker
  - status
  - short SHA
  - tests
  - binary
  - started
  - duration
  - commit message
- Default to 20 rows.
- No target summary header.
- Short SHA everywhere.
- Truncate commit messages based on terminal width using existing terminal-width helpers where practical.

Confirmation prompts:

- `delete <sha>` prompts unless `--yes`.
- `remove-binary <sha>` prompts unless `--yes`.
- `--skip-tests` prompts or requires `--yes` when target testing is enabled.

## Crash Recovery

Define transient statuses as:

- `building`
- `testing`
- `restoring`

Repair rule:

- If an operation is open/running and Operation lock is not held, it is abandoned.
- If the associated deployment row is transient, mark it `failed`.
- Append a recovery note to `Deployment.output`, preserving prior transcript if present.
- Mark operation `failed` and clean up events after final output persistence.

Do not repair if the Operation lock is held:

- Treat the operation as active.
- Server attaches to Operation event stream.
- CLI read operations may observe and follow output.

Repair entrypoints:

- server boot before panel registration finishes and before `drainOnBoot()`
- CLI headless runtime startup before listing or starting work

Panel parity:

- Panel deploy crash and CLI deploy crash use the same repair code.
- A panel deploy crash usually releases the lock because the server process owned execution.
- A CLI deploy keeps running if only the server crashes; the server reattaches when it restarts.

## Tests And QA

There is currently no `Tests/` directory. Add a test target if feasible; otherwise create focused testable units and document manual QA clearly.

Automated tests should cover:

- SHA resolver:
  - full SHA
  - unique prefix
  - ambiguous prefix
  - unknown reachable SHA from configured branch
  - unknown unreachable SHA
- Operation lock:
  - acquire succeeds when free
  - acquire fails when held
  - read-only commands do not require lock
  - update/deploy mutual exclusion
- Operation event stream:
  - sequence ordering
  - log ANSI stripping
  - event cleanup after final output persistence
  - attach/replay reads existing events
- Deployment engine:
  - promote live deployment no-ops successfully
  - promote saved binary restores
  - promote no-binary builds/runs/archives
  - `--testing` forces inline test for no-binary promote
  - `--skip-tests --yes` skips configured testing
  - `--testing` on saved binary refuses
  - build refuses existing binary
  - run refuses missing binary
  - test preserves prior lifecycle status
  - delete refuses live deployment
  - remove-binary resets row to `pushed`
- Recovery:
  - open operation plus no lock repairs transient row to failed
  - open operation plus held lock does not repair
  - repair runs from server boot and CLI startup paths

Manual QA should cover:

- `deployerctl deploy` list matches panel rows and uses short SHA.
- Panel shows short SHA and copy copies full SHA.
- CLI deploy while server offline succeeds.
- CLI deploy while panel is open streams logs into the panel.
- Server starts mid-CLI-deploy and attaches to live output.
- Server restarts mid-CLI-deploy and reattaches to live output.
- Panel deploy crash repairs to failed on next boot.
- Operation lock prevents panel/CLI concurrency in both directions.
- Existing `deployerctl update` still works.
- Existing wrapper service controls still work.

## Suggested Implementation Order

1. Add operation models, migrations, and `OperationLock`.
2. Add headless runtime setup for deployment CLI commands.
3. Add SHA resolver and deployment catalog/list presenter.
4. Extract operation output/event sink from `BuildOutputStream`.
5. Extract `DeploymentEngine` and refactor `Worker` to use the new sink.
6. Refactor `Queue` and panel row actions onto `DeploymentEngine`.
7. Add operation event consumer that bridges to Mist.
8. Implement CLI commands and console rendering.
9. Update `deployerctl` wrapper.
10. Update panel SHA display.
11. Add tests and run manual QA.

## Acceptance Criteria

- Another process holding `.deployer-operation.lock` prevents all mutating panel and CLI operations.
- `deployerctl deploy <sha>` can complete with the server stopped.
- CLI-origin operation logs appear live in the panel when the server is online.
- Server can attach to an in-progress CLI operation after start/restart.
- Panel and CLI use the same deployment operation code paths.
- Panel and CLI both show short Git SHA as the human deployment identifier.
- Automatic webhook/boot drain semantics are preserved.
- Manual panel and CLI operations target exactly the selected commit.
- `deployerctl update` behavior remains intact.
