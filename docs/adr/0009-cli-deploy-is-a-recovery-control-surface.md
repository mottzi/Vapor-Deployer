---
status: proposed
---

# CLI deploy is a recovery control surface

`deployerctl deploy` is a recovery-grade target-app deployment command: it must remain usable when the Deployer server and panel are offline, while still causing the online panel to live-update through Mist, including deployment logs. Panel actions and CLI actions must share the same underlying deployment engine rather than carrying separate deployment behavior.

The human selector for CLI deployment is the Git commit SHA, including unambiguous SHA prefixes; deployment UUIDs are diagnostic details, not normal operator input. `deployerctl deploy <sha>` promotes the selected commit, restoring an existing saved binary by default when one is available, and per-job test flags such as `--testing` and `--skip-tests` affect only that invocation rather than mutating target configuration.

Mutating panel and CLI operations are serialized by a shared cross-process Operation lock. Mutations fail fast when another operation is running; read-only commands such as listing deployments and reading logs remain available while the lock is held.

The Operation lock lives in the install directory as `.deployer-operation.lock`. The runtime badge treats a held operation lock as `deploying`, even when the server's in-memory operation coordinator is idle, and panel actions are disabled while the lock is held with conflict handling as the race-safe fallback.

CLI promotion targets exactly the selected commit. It does not drain newer queued webhook pushes.

CLI-origin operations publish status and log output to a durable Operation event stream. When the server is online, it consumes that stream and rebroadcasts row updates and log output through Mist; if the server starts or restarts during a CLI deploy, it must attach to the active operation and replay enough stream state for the panel to catch up.

The live-output transport is intentionally asymmetric. Server-origin operations already run inside the process that owns Mist, so they stream directly to Mist in-process and do not persist live `OperationEvent` chunks to SQLite. CLI-origin operations run in a separate process, so they pay the SQLite write cost only to cross that process boundary and to buffer output across transient server restarts. `deployerctl output <sha>` therefore follows only active CLI-origin operations; for server-origin work, the CLI can read the final `Deployment.output` transcript after it is persisted, but it is not a live panel-to-CLI tail.

The Operation event stream is stored in the existing SQLite database using `operations` and `operation_events` tables for CLI-origin bridge delivery. Its v1 event vocabulary is `started`, `row-updated`, `row-deleted`, `log-appended`, `service-status`, `completed`, and `failed`. Log events store stripped plain text only. Final deployment transcripts continue to be persisted to `Deployment.output` at the end of the operation; operation events are deleted once the deployment reaches a terminal state and the final output has been persisted.

Rejected alternatives:

- **CLI streams directly to the server over HTTP, sockets, or WebSocket.** Rejected because the CLI would need retry, reconnect, and local buffering logic to avoid losing log chunks while the server restarts. Without that buffering, the panel could not catch up after a transient server failure; with it, the direct channel has recreated the SQLite bridge with more moving parts.
- **Persist server-origin live output to SQLite too.** Rejected because it duplicates the hot server-to-Mist path and adds disk I/O to the common panel-started deployment path only to support a niche reverse tail from `deployerctl output`. The final transcript remains persisted in `Deployment.output`, which preserves the durable audit surface without making SQLite a general bidirectional live-output bus.

Unknown SHAs are allowed only when they can be resolved from the configured branch. The CLI creates the missing Deployment row automatically in that case; otherwise it refuses.

Saved-binary promotion remains a fast restore by default. `--testing` does not create a CLI-only test-gated restore path in v1; when the selected deployment already has a saved binary, the command refuses and tells the operator to run the explicit test action first.

Automatic webhook and boot-drain flows keep their newest-eligible-push behavior, but operator deployments from the panel and CLI target exactly the selected commit.

The CLI deployment feature is scoped to deployment-row control. Target environment editing remains out of scope for this decision.

The v1 CLI favors interactive operator UX over automation breadth: mutating commands wait until completion, stream logs by default, support `--no-logs`, and do not include `--detach` or `--json`. CLI target-app work runs as the configured service user, matching server-origin deployments rather than the root-owned self-update path.

The v1 command surface uses top-level deployment verbs: `deploy` lists deployments, `deploy <sha>` promotes a commit, `build <sha>` builds and saves a binary, `run <sha>` restores a saved binary, `test <sha>` runs the manual test audit, `output <sha>` shows deployment output, `delete <sha>` deletes a deployment row, and `remove-binary <sha>` removes a saved binary. `deploy` list output does not include a target summary header; operators can use `config` for configuration details.

Promoting the live deployment exits successfully with an "already live" message and makes no change. `build <sha>` refuses the live deployment and deployments that already have a saved binary, matching the panel.

The top-level row actions keep panel parity: `run <sha>` refuses the live deployment or if the saved binary is missing on disk, `remove-binary <sha>` refuses the live deployment and otherwise resets the row to `pushed`, `delete <sha>` refuses the live deployment, and `test <sha>` is allowed on the live deployment because tests are audits. `output <sha>` follows live CLI-origin output until completion and otherwise prints stored output when available.

`deploy` lists the same newest-first deployment rows as the panel, defaulting to 20 rows. Human-facing deployment identifiers are short Git SHAs everywhere in the panel and v1 CLI; deployment UUIDs remain internal identifiers for Mist, persistence, and diagnostics.

Panel and CLI operations use the same crash-recovery rule. Server boot and CLI command startup repair abandoned operations before listing or starting new work: if no Operation lock is held but an operation is open and its deployment row is still transient, the row is marked `failed` and the output receives a recovery note. If the Operation lock is still held, the server treats the operation as active and attaches to the Operation event stream instead of repairing it.
