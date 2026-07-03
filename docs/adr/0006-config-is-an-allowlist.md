# `deployer config` is an allowlist over `deployer.json`, not a free editor

The `deployer config` CLI lets an operator change `deployer.json` in place without re-running setup. The naive shape is "let it edit any field, print warnings for risky ones." We picked the inverse: an explicit allowlist of 6 fields, with every other field of `Configuration` / `TargetConfiguration` refused at the CLI with a message redirecting to `deployer setup`. The reason is that the 21 fields are not uniformly editable — most are entangled with state on disk that the JSON only *records*, so a JSON-only edit desynchronizes the recorded value from the real fact and corrupts the install. The allowlist makes "what `config` can safely change" a single, audit­able set instead of asking every operator (and every reviewer of a future field addition) to re-derive the entanglement analysis from scratch.

## What's editable

- `deployerBranch` *(source installs only — refused on binary installs because the field is meaningless there)*
- `target.branch`
- `target.buildMode`
- `target.deploymentMode`
- `target.binaryBehaviour`
- `target.testing`

## What's refused, and why

`config` refuses the remaining 15 fields with an error that names the reason and points at `deployer setup`:

- **Baked into the rendered nginx site** at setup time (`Sources/Deployer/Commands/Setup/Templates/NginxTemplate.swift`): `port`, `panelRoute`, `target.appPort`, `target.pusheventPath`. A JSON-only change leaves nginx still proxying the old value; the panel or webhook silently breaks.
- **Names a fact about files on disk** that the JSON only records, not controls: `dbFile` (SQLite path — JSON-only change abandons history), `deployerDirectory` (install anchor for lockfile + control token), `socketPath`, `target.directory` (target checkout location), `target.repositoryURL` (the local clone's git remote was set at clone time and is not rewritten by the JSON), `target.name` (Swift product name + service unit name).
- **Describes how this install was provisioned**, not a preference: `serviceBackend` (host init system, chosen by Setup based on the OS), `buildFromSource` (the updater branches on this to choose pull-and-rebuild vs. download-binary; flipping it lies about the install layout).
- **Lives in more places than `deployer.json`**: `webhookSecret` is also exported as `GITHUB_WEBHOOK_SECRET` in the systemd / supervisor unit (the env var is what the running process reads) and is installed on GitHub via the GitHub API by `WebhookStep`. The JSON field is a *record* of "what secret was provisioned," not the live source. Rotating it requires re-rendering the unit and pushing the new secret to GitHub — work `SetupCommand.evaluateWebhookState` already does idempotently. Adding a parallel rotation path inside `config` would duplicate `WebhookStep` + `collectGitHubToken` + the unit re-render for a rare operation.

## Considered alternatives

- **"Edit anything; print warnings for risky fields."** Cheaper to implement and friendlier in principle. Rejected because the failure mode for the corrupting fields is *silent breakage on next restart* — a warning printed once at edit time is not a load-bearing safety mechanism. The cost of refusing a legal-but-rare change is a clear error message; the cost of accepting an unsafe change is a broken install diagnosed later. Asymmetric in favour of refuse-by-default.
- **Reuse `SetupCommand`'s write path** (the `DeployerTemplate` compose-from-`SetupContext`). Rejected because Setup writes a fresh `Configuration` composed from inputs; `config` does decode-mutate-encode of an existing JSON. Forcing both through one helper twists both. `config` shares only `Configuration.getConfigURL` and the `JSONEncoder` settings (so file shape doesn't churn between Setup-written and config-written states).

## Consequences

- Adding a new editable field is an explicit, reviewable change to the allowlist plus (if applicable) a justification of why it isn't entangled with on-disk state.
- Validation is delegated to `Configuration.resolved()` via a decode-mutate-resolved-encode round-trip: the same function that gates the boot path gates the write path, so `config` cannot persist a JSON the deployer would reject at next load.
- The write is atomic (`<configURL>.tmp` → `fsync` → `rename(2)`) with no `.bak`. Atomic write + load-path validation eliminates the failure modes a backup would protect against, and one-shot `.bak` files were already observed to accumulate stale on production.
- The restart preflight mirrors `UpdateCommand.preflightControlQuery` (ADR 0005): a `GET /control/state` query before any write, refusing the whole operation when `phase != "ready"`. Connection-refused is treated as proceed (the server is down, restarting it just starts it); 401/403/404/5xx are `serverUnhealthy` and refuse. The user-says-N-to-restart path writes the JSON and exits with a reminder — the JSON is the durable source of truth, and staging a change against the next restart is a legitimate workflow.
- The operator surface is `deployerctl config [<key> <value>]`, mirroring `deployerctl update` / `setup` / `remove`: the shell wrapper exec's the Swift binary after the EUID check, forwarding positional arguments. Root-only for both read and write, because `deployer.json` is mode-0600 owned by the service user — a non-root invocation cannot open the file regardless. The Swift command performs its own restart via `ServiceBackend.makeManager(...).restart(product:)` (the same primitive `SetupCommand` rollback uses), not by shelling back out to `deployerctl restart deployer`. The wrapper's `/etc/deployer/deployerctl.conf` env-var dump is unrelated and unchanged — it feeds the shell script's service-control needs; the Swift `config` command reads `deployer.json` directly via `Configuration.getConfigURL`.
