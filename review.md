I've now read every file in `Sources/Deployer/Commands/` plus the supporting infrastructure (`App/`, `Service/`, `Deployment/Shell.swift`, `Error/`) and the `setup.sh` bootstrapper. No files were modified. Here is the full analysis.

# Vapor-Deployer code review: `Commands/` + `setup.sh`

## 1. High-level shape of the command layer

`Commands/` contains five sibling areas:

```
Commands/
├── Setup/       (command + context + step protocol + 20 steps + 6 templates)
├── Remove/      (command + context + step protocol + 10 steps)
├── Update/      (command + context + step protocol + 6 steps)
├── Version/     (trivial command + DeployerVersion resolver)
└── System/      (shared infra: preconditions, paths, shell, errors, console, release assets, GitHub API, deployerctl config discovery)
```

The three "big" commands (`Setup`, `Remove`, `Update`) are structurally parallel:

1. A `XCommand: AsyncCommand` with a `Signature`, a fixed list of step types, and a simple `for step in steps { step.printHeader; try await step.run() }` loop.
2. A shared mutable `XContext` class that all steps read and write.
3. A tiny `XStep` protocol with `title`, `context`, `console`, `init(context:console:)`, `run()`.

`Version` is an outlier: it doesn't have a context, steps, or even a signature-based config — it's just a one-line `print(DeployerVersion.current())`.

The runtime server (`App/Bootstrap.swift`) sits alongside commands and consumes `Configuration.load()` + `ServiceManager` at `serve` time. Setup steps write the `deployer.json` that this server later reads.

---

## 2. `deployerctl` — what it is, how it's built, why root matters

### 2.1 Purpose

`deployerctl` is an **operator-facing bash wrapper** installed at `/usr/local/sbin/deployerctl` that provides a thin, configuration-aware control surface over the deployer + managed app services. It is the only command end-users are expected to run after the initial bootstrap (`setup.sh`). Its documented interface is:

```
sudo deployerctl <action> [target]
  actions: status, start, stop, restart, reload, enable, disable,
           logs, journal, version, setup, update, remove
  targets: deployer | app | all (default: all)
```

### 2.2 Generation pipeline

`deployerctl` is produced entirely by Swift code, in one step of the setup pipeline:

- Template source: `Commands/Setup/Templates/DeployerctlTemplate.swift`
  - `wrapperScript()` — static body of the bash script (no interpolation — the script relies on a sibling config file, read at invocation time)
  - `wrapperConfig(context:)` — POSIX shell-safe `KEY='value'` pairs derived from `SetupContext` + `SystemPaths`, escaped via `TemplateEscaping.shellLiteral`
- Installer step: `Commands/Setup/Steps/DeployerctlStep.swift` — writes `paths.deployerctlConfig`, then writes `paths.deployerctlBinary` with `mode: "0755"`. Both destinations are hard-coded in `SystemPaths.derive`:
  - `deployerctlBinary        = /usr/local/sbin/deployerctl`
  - `deployerctlConfigDirectory = /etc/deployer`
  - `deployerctlConfig        = /etc/deployer/deployerctl.conf`

### 2.3 `/etc/deployer/deployerctl.conf` — the contract

The config is a flat, sourceable shell file. Every value is wrapped in single quotes via `TemplateEscaping.shellLiteral` (which also handles embedded single quotes via `'"'"'`). 21 keys (in template order):


| Key                           | Source                                     | Consumer                                                  |
| ----------------------------- | ------------------------------------------ | --------------------------------------------------------- |
| `SERVICE_USER`                | `context.serviceUser`                      | deployerctl script, Remove, Update                        |
| `SERVICE_MANAGER`             | `context.serviceManagerKind.rawValue`      | deployerctl script, Remove, Setup re-runs                 |
| `PRODUCT_NAME`                | `context.productName`                      | deployerctl script (targets `app`), Remove, Setup re-runs |
| `APP_NAME`                    | `context.appName`                          | Setup re-runs, Remove                                     |
| `APP_REPO_URL`                | `context.appRepositoryURL`                 | Setup re-runs (default)                                   |
| `APP_PORT`                    | `context.appPort`                          | Setup re-runs (default)                                   |
| `TLS_CONTACT_EMAIL`           | `context.tlsContactEmail`                  | Setup re-runs (default)                                   |
| `INSTALL_DIR`                 | `paths.installDirectory`                   | deployerctl `resolve_install_bin`, targets                |
| `APP_DIR`                     | `paths.appDirectory`                       | deployerctl validation                                    |
| `DEPLOYER_LOG`                | `paths.deployerLog`                        | deployerctl `logs` action                                 |
| `APP_LOG`                     | `{appDeployDirectory}/{productName}.log`   | deployerctl `logs` action                                 |
| `PRIMARY_DOMAIN`              | `context.primaryDomain`                    | Setup re-runs, orphan detection                           |
| `ALIAS_DOMAIN`                | `context.aliasDomain`                      | (set but not consumed)                                    |
| `CERT_NAME`                   | `context.certName`                         | Remove, Setup orphan cleanup                              |
| `NGINX_SITE_NAME`             | `paths.nginxSiteName`                      | (set but not consumed in code)                            |
| `NGINX_SITE_AVAILABLE`        | `paths.nginxSiteAvailable`                 | Setup cleanup, Remove                                     |
| `NGINX_SITE_ENABLED`          | `paths.nginxSiteEnabled`                   | Setup cleanup, Remove                                     |
| `ACME_WEBROOT`                | `paths.acmeWebroot`                        | Remove                                                    |
| `CERTBOT_RENEW_HOOK`          | `paths.certbotRenewHook`                   | Setup cleanup, Remove                                     |
| `WEBHOOK_PATH`                | `paths.webhookPath`                        | Remove summary                                            |
| `GITHUB_WEBHOOK_SETTINGS_URL` | `github.com/{owner}/{repo}/settings/hooks` | Remove summary                                            |


The Swift-side reader is `Commands/System/Shared/ConfigDiscovery.loadDeployerctl(configPath:)`, which **sources** the file via `bash -c`, then prints each key as `KEY\0VALUE\0` for the Swift parser. This is the correct choice (shell variables with `$` escaping must be resolved by an actual shell), but it means the list of readable keys is **hand-maintained in two places**:

- `DeployerctlTemplate.wrapperConfig` — the writer
- `ConfigDiscovery.deployerctlKeys` — the reader

There is no structural guarantee they stay in sync.

### 2.4 How the script behaves — and why running as root matters

`deployerctl` is designed to be invoked as root (either directly on a root shell or via `sudo`). The installed binary has no setuid bit; root is enforced by `[[ $EUID -eq 0 ]] || die "..."` (with a hard-coded exception for `version`, so it is usable in degraded states).

Because the deployer service runs **under a dedicated service user (default `vapor`) via `systemctl --user`**, and `deployerctl` itself runs as **root**, the script must explicitly bridge two identities every time it wants to talk to the user systemd instance. Concretely:

1. `loginctl enable-linger "$SERVICE_USER"` so the user manager keeps running without an active login session (idempotent; ignored on error).
2. `systemctl start "user@${SERVICE_UID}.service"` so the user manager is actually up.
3. Busy-wait up to ~5s for `/run/user/${SERVICE_UID}/bus` to appear.
4. `cd "$SERVICE_HOME"` (or `/` as a fallback) so tools started as that user don't inherit `/root`.
5. Every systemctl/journalctl call is wrapped in:
  ```
   runuser -u "$SERVICE_USER" -- env \
     HOME=... USER=... \
     XDG_RUNTIME_DIR=/run/user/$SERVICE_UID \
     DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$SERVICE_UID/bus \
     systemctl --user ...
  ```

Without (3) and (5), `systemctl --user` from a root context would either fail to find the user bus or target root's own user session — a classic footgun.

The same root-context bridge is **implemented three more times in Swift**:

- `Commands/System/SystemShell.swift::runUserSystemctl(_:_)` (uses `systemdUserEnvironment(uid:)` + `runuser` via `runuserCommand`)
- `Commands/System/SystemShell.swift::waitForUserBus(uid:timeout:)`
- `Service/SystemdServiceManager.swift::prefix` — builds `XDG_RUNTIME_DIR=/run/user/$(id -u USER) DBUS_SESSION_BUS_ADDRESS=...` as a **bash-interpolated command-prefix string** used with `Shell.run("bash -c ...")`

That's four independent encodings of the same lifecycle — with subtle differences:


| Aspect                    | `deployerctl` (bash) | `SystemShell.runUserSystemctl` | `SystemdServiceManager.prefix`                                          | `DeployerctlTemplate update` action |
| ------------------------- | -------------------- | ------------------------------ | ----------------------------------------------------------------------- | ----------------------------------- |
| Enables linger            | yes                  | no                             | no                                                                      | yes                                 |
| Waits for bus socket      | yes (50×100ms)       | yes (≤5s)                      | no                                                                      | yes (50×100ms)                      |
| Starts `user@UID.service` | yes                  | no                             | no                                                                      | yes                                 |
| Uses `runuser`            | yes                  | yes                            | no (stays in root, relies on `XDG_RUNTIME_DIR=/run/user/$(id -u USER)`) | yes                                 |
| Passes `HOME`/`USER`      | yes                  | yes (as env map)               | no                                                                      | yes                                 |


The `SystemdServiceManager.prefix` branch is the shakiest: when run as root, `XDG_RUNTIME_DIR=/run/user/$(id -u USER)` alone is insufficient unless the user's `user@<uid>.service` is already up **and** root already has the right credentials to talk to that bus (systemd historically allows `uid=0` to talk to any user bus, so this usually works, but it is not the same contract as `deployerctl`'s). The runtime `ServiceManager` is also invoked from `UpdateCommand.rollback` / `StopServiceStep` / `StartServiceStep` — which are root-invoked via `deployerctl update` — so this asymmetry matters.



---

## 3. Code smells and structural issues

I've grouped findings by severity / type. Each has a file+line anchor.

### 3.1 Three near-identical command scaffolds (Setup/Remove/Update)

All three command types share the exact same template:

- `XCommand.run(using:signature:)` — require preconditions, build context, map step types through `{ $0.init(context:, console:) }`, print banner, iterate with numbered header.
- `XContext: SystemContext` — stores `serviceUser`, `serviceUserUID`, `paths`, `serviceManagerKind`.
- `XStep` protocol — `title`, `context`, `console`, `init`, `run()` + extension providing `shell: SystemShell` and `printHeader(index:total:)`.

The only meaningful variation:


|                                 | Setup                          | Remove                         | Update                         |
| ------------------------------- | ------------------------------ | ------------------------------ | ------------------------------ |
| Header color                    | cyan                           | red                            | yellow                         |
| `paths` accessor                | `preconditionFailure` if nil   | `preconditionFailure` if nil   | (none — paths always nil)      |
| Extra helpers                   | —                              | `bestEffort(_:_:)`             | —                              |
| `requireRoot` + `requireUbuntu` | yes                            | yes                            | no                             |
| Context type hierarchy          | `final class`, `SystemContext` | `final class`, `SystemContext` | `final class`, `SystemContext` |


This is ~180 LOC of boilerplate that would collapse behind one generic protocol, one `Pipeline<Context>` type, and a single `CommandStyle` / palette enum for color + banner. Relevant files: `Setup/SetupCommand.swift`, `Setup/SetupStep.swift`, `Remove/RemoveCommand.swift`, `Remove/RemoveStep.swift`, `Update/UpdateCommand.swift`, `Update/UpdateStep.swift`.

### 3.14 Configuration-key lists that must stay in sync

Manual, parallel string-lists across four writers/readers:

- `DeployerctlTemplate.wrapperConfig` (writes 21 keys)
- `ConfigDiscovery.deployerctlKeys` (reads 21 keys)
- `InputStep`, `CleanupOrphansStep`, `NginxStep`, `RemoveInputStep` — each pulls specific keys out of `metadata["…"]`
- `deployerctl` bash script — consumes a different subset (`INSTALL_DIR`, `APP_DIR`, `DEPLOYER_LOG`, `APP_LOG`, `SERVICE_USER`, `SERVICE_MANAGER`, `PRODUCT_NAME`, plus the mandatory-fields guard on line 186)

No typed schema. Any new key requires touching all four places by hand. Candidate for a single Swift type that models the conf file and has `write(to:)` + `load(from:)` + an exhaustive key-list.

### 3.15 "Previous state" is scattered, not owned

`SetupContext.previousMetadata: [String: String]?` is populated once in `InputStep` and then read opportunistically by:

- `InputStep.collectServiceUser` (lock on existing user)
- `InputStep.collectTargetRepository`/`collectPorts`/`collectPanelRoute`/... (defaults)
- `CleanupOrphansStep` (orphan detection)
- `NginxStep.cleanupPreviousFiles` (stale site removal)

Defaulting, cleanup, and orphan detection are three different concerns threaded through the same untyped dictionary. A small typed snapshot (e.g. `PreviousInstallation` struct) loaded once and passed to each step would make the dependencies explicit and would remove ~10 ad-hoc `metadata["KEY"] ?? ""` sites.

### 3.16 `InputStep` is 280 LOC and mixes concerns

`Commands/Setup/Steps/InputStep.swift` does:

1. Load `deployerctl.conf` metadata
2. Load `deployer.json`
3. Collect ~12 prompts
4. DNS-resolve both domains (live network I/O)
5. Generate a hex secret from `/dev/urandom`
6. Verify the GitHub token via live API call
7. Derive `SystemPaths`
8. Print a summary card

Items 1–3 are "collect"; 4–6 are validation against the live world; 7 is derivation; 8 is output. Good splitting point if you decide to break it up.

### 3.17 `ResolveProductStep` parses `Package.swift` with a line-regex state machine

`Commands/Setup/Steps/ResolveProductStep.swift:24–47` implements a fragile mini-parser for `.executable(` / `.executableTarget(` blocks. It misreads (silently) when `.executable(` or `name: "…"` appear anywhere unexpected (string literals, multi-line product declarations, comments). A single-shot invocation of `swift package dump-package` (JSON) or `swift package describe --type json`, executed as the service user, is the robust replacement.

### 3.18 Git operations duplicated

Three separate "fetch / checkout / pull" sequences:

- `Setup/Steps/StageDeployerStep.installFromSource()` — deployer repo
- `Setup/Steps/AppCheckoutStep.updateRepository()` — app repo
- (Plus remote-URL normalization in `PreflightStep.normalizeGithubRemote`, which is yet another ad-hoc normalizer next to `InputValidator.parseGitHubSSHURL`)

A small `GitRepository(path: String, shell: SystemShell)` value type with `fetch`, `checkout`, `pullFastForward`, `clone`, `origin`, `isDirty`, `hasGitDirectory` would eliminate both the duplication and the two different flavors of URL-matching.

### 3.20 `UpdateCommand.rollback` reaches across layer boundaries

`UpdateCommand.swift` imports `Configuration`, `ServiceManager`, `SystemFileSystem`, `ReleaseAssetBackup` directly, and also redefines its own restore/status-wait helpers that largely mirror what the step files already do. Rollback is effectively a **seventh step that doesn't fit the step model** (it runs only on error from `ActivateReleaseStep` / `StartServiceStep`). That's fine as a concept — rollback is genuinely different — but the current implementation re-does too much step-level work in the command itself.

### 3.21 `SystemContext.paths` optional is misleading

The protocol says `var paths: SystemPaths? { get }`. All three concrete contexts expose `var paths: SystemPaths?` with a setter. Each step protocol then re-wraps this in a non-optional helper that `preconditionFailure`s on nil. This is a widely-used pattern but carries two drawbacks:

- The protocol doesn't express the actual contract ("after InputStep, this is non-nil"), so the step ordering is a runtime invariant.
- `UpdateContext.paths` is never set at all, satisfying the protocol with a lie.

A cleaner shape is a two-phase type: `PartialXContext` during `InputStep`, then `ResolvedXContext` afterwards. Or simply remove `paths` from `SystemContext` and let each step type declare what it actually depends on.

### 3.22 Root-context env propagation is partially re-discovered at call sites

Because `deployerctl` runs as root, every Swift entry invoked through it inherits root's shell environment (PATH, HOME=/root, XDG_RUNTIME_DIR=/run/user/0 if any, no DBUS address). Several command flows then manually re-derive a sane environment at the call site:

- `SwiftStep` (`userEnvironment = [HOME, USER]`)
- `BuildStep` (`buildEnvironment = [HOME, USER, PATH]`)
- `SystemShell.serviceUserEnvironment(merging:)` (`HOME, USER`)
- `SystemShell.systemdUserEnvironment(uid:)` (`XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS`)

These share no common source of truth. A single `ServiceUserEnvironment(paths:)` value type with `.shell`, `.build`, `.systemd` views would make the root-context contract explicit.

### 3.23 `setup.sh` has its own duplicate sources of truth with Swift

Hard-coded in both `Resources/Scripts/setup.sh` and `Commands/System/Shared/DeployerReleaseAssets.swift`:

- Repository slug `mottzi/Vapor-Deployer`
- Asset pattern `deployer-linux-${ARCH}.tar.gz`
- Env key `DEPLOYER_RELEASE_TAG`

The bootstrap script also hard-codes `/tmp/deployer-${VERSION}` as its staging root and `./deployer setup` as its entry point. None of these are validated against the Swift side at build or CI time — each is a drift risk.

### 3.24 Miscellaneous smaller issues

---

## 4. Module boundaries / layering observations

Today, `Commands/System/` is labeled "shared system infra" but has three kinds of code living together:


| Group                                            | Files                                                                                          | Concerns                                                                                                         |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Preconditions & context contract                 | `SystemPreconditions.swift`, `SystemContext.swift`, `SystemError.swift`                        | OS/OS-version assertions; protocol for command state                                                             |
| File/shell primitives                            | `SystemShell.swift`, `SystemFileSystem.swift`, `SystemPaths.swift`                             | Invoking external commands, writing files, path derivation                                                       |
| Command-specific helpers pretending to be shared | `Shared/ConfigDiscovery.swift`, `Shared/DeployerReleaseAssets.swift`, `Shared/GitHubAPI.swift` | deployerctl.conf parsing (Setup + Remove + Update), release assets (Setup + Update), GitHub API (Setup + Update) |
| Console UX                                       | `Console/ConsolePrompt.swift`, `Console/ConsoleSection.swift`, `Console/InputValidator.swift`  | Interactive prompts + formatting + validation                                                                    |


Meanwhile, `App/` owns `Configuration`, which is consumed by both runtime and commands. `Service/` owns `ServiceManager`, used partially (runtime + Update, but **not** Setup/Remove).

A cleaner split — without inventing new modules — might be:

- `Shared/` (or just `Support/`): shell, file system, paths, config discovery, release assets, GitHub API, validator, console, preconditions, errors.
- `Commands/<Command>/`: command + context + pipeline glue + steps only.
- `Service/`: a single `ServiceManager` abstraction actually used by **all three** commands for start/stop/enable/disable/write-unit/remove-unit, so each `Step` stops doing its own `switch serviceManagerKind`.

---

## 5. Summary of the biggest opportunities

Ranked by how much redundancy removal each one enables:

1. **Unify the three command pipelines.** One generic `Pipeline<Context>`, one step protocol, one place for `printHeader`, `bestEffort`, `shell`, `paths`. Collapses `XStep.swift` / `XCommand.swift` boilerplate.
2. **Make `ServiceManager` the one way to control services.** Extend it with `writeUnit`, `removeUnit`, `enable`, `disable`, `reload`, `waitForStable`. Every `switch context.serviceManagerKind` in Setup/Remove disappears.
3. **Turn `deployerctl.conf` into a typed value.** One struct with a canonical key list, `encode()`, `decode(from:)`. Both the template and `ConfigDiscovery` go through it. The bash script's required-key list lives next to the Swift schema.
4. **Consolidate the root→service-user bridge.** One Swift type (`ServiceUserContext`) + one bash function set (emitted from one place) that handles `enable-linger`, `user@.service` up, bus-wait, `runuser env` — instead of four independent reimplementations (`SystemShell`, `SystemdServiceManager.prefix`, `deployerctl.ensure_user_manager`, `deployerctl.update` inline).
5. **One path layer for all commands.** Remove `SystemPaths?` from `SystemContext`; either hand derived paths in as a step dependency or give Update its own typed install-layout value so the optional lie goes away.
6. **Merge the three release-asset entry points** into one `DeployerReleaseAssets.resolve(source:into:)` API with explicit source cases (`inPlace`, `pinned(tag:)`, `latest`).
7. **Pick one of `shellQuoted` / `shellLiteral`** (plus one `terminalWidth`/`tputColumns`). Fold `PreflightStep.normalizeGithubRemote` into `InputValidator`.
8. **Introduce a typed "previous installation snapshot"** populated once, consumed explicitly by the steps that care (defaults, orphan detection, stale-file cleanup) — replacing the `metadata["KEY"] ?? ""` pattern.
9. **Reuse runtime `Configuration` more, not less, at setup time.** Today setup writes `deployer.json` but re-derives all the same values itself. A "resolved configuration" object could be the single source of truth fed into templates.
10. **Replace `ResolveProductStep`'s regex parser** with `swift package describe --type json` run as the service user. Removes one fragile mini-parser.

No repository files were changed during this review.

## 6. Refactor documentation

Brief log of changes completed after this review was written.

- **3.2 addressed (banner/header placement cleanup):**
  - Command banners and step-header rendering were moved to command-owned helpers in:
    - `Commands/Setup/SetupCommand.swift`
    - `Commands/Remove/RemoveCommand.swift`
    - `Commands/Update/UpdateCommand.swift`
  - Command-specific banner/titled-rule helpers were removed from shared console files and step files.
- **Console formatting simplification:**
  - `Commands/System/Console/ConsoleSection.swift` now provides small generic helpers (`newLine()`, `ruler(...)`) used by commands and summary/card output.
  - `card` call sites were renamed from `kvs:` to `keyedValues:` for readability.
- **Bug fix after refactor:**
  - Fixed titled-ruler fill-width calculation in `ConsoleSection.ruler(_ title: ...)` to correctly subtract prefix/title width from terminal width.
- **3.13 addressed (dead error-case cleanup):**
  - Removed unused `releaseAssetNotFound(String)` cases from:
    - `Sources/Deployer/Error/SetupError.swift`
    - `Sources/Deployer/Error/UpdateError.swift`
  - Verified with a successful `swift build`.
- **3.24 addressed (orphan cleanup simplification):**
  - Simplified `CleanupOrphansStep` file-removal helpers by removing redundant `fileExists` pre-checks while preserving best-effort deletion behavior with `try?`.
  - Updated:
    - `Sources/Deployer/Commands/Setup/Steps/CleanupOrphansStep.swift`
  - Verified with a successful `swift build`.
- **3.24 addressed (unused `SystemPaths.appBinary` removal):**
  - Removed unused `SystemPaths.appBinary`, which previously duplicated `appDeployDirectory` and was not referenced by any call site.
  - Updated:
    - `Sources/Deployer/Commands/System/SystemPaths.swift`
  - Verified with a successful `swift build`.
- **3.24 addressed (shared summary-row formatting):**
  - Added `Console.summaryRow(_:_:)` and reused it in both `Console.card(...)` and `RemoveSummaryStep` to remove duplicated alignment logic while preserving output format.
  - Updated:
    - `Sources/Deployer/Commands/System/Console/ConsoleSection.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveSummaryStep.swift`
  - Verified with a successful `swift build`.
- **3.24 addressed (path-source reuse in remove cleanup):**
  - Replaced inline path construction in `RemoveCheckoutsStep` with existing `SystemPaths` properties (`deployerBinary`, `deployerConfig`, `deployerLog`, `appDeployDirectory`) while preserving deletion behavior and order.
  - Updated:
    - `Sources/Deployer/Commands/Remove/Steps/RemoveCheckoutsStep.swift`
  - Verified with a successful `swift build`.
- **3.24 addressed (stale review note removal):**
  - Removed the outdated note about dead `SetupError`/`UpdateError` release-asset siblings after prior cleanup removed those enum cases.
  - Updated:
    - `review.md`
- **3.24 addressed (shared `getent` home-directory lookup):**
  - Extracted the `getent passwd` home-directory helper into `UserAccount.homeDirectory(for:errorLabel:)`, reused by both `PreflightStep` and `RemoveInputStep.collectServiceUser()` so setup and remove no longer disagree on user lookup.
  - `PreflightStep` preserves its exact `"serviceUser"` error label for the unchanged malformed-output branch; `RemoveInputStep` preserves its existing console messages.
  - Added:
    - `Sources/Deployer/Commands/System/Shared/UserAccount.swift`
  - Updated:
    - `Sources/Deployer/Commands/Setup/Steps/PreflightStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveInputStep.swift`
  - Verified with a successful `swift build`.
- **3.24 discarded (bash `/dev/tcp` health-check note):**
  - Removed the `HealthStep.waitForTCP` fragility note as not necessary to action right now.
  - Updated:
    - `review.md`
- **3.24 discarded (comment-only setup-context note):**
  - Removed the `SetupContext.panelRoute`/`deploymentMode` note because the action was comment/documentation-only.
  - Updated:
    - `review.md`
- **3.24 addressed (remove redundant `deployerSocketPath` field):**
  - Removed `SystemPaths.deployerSocketPath` and inlined the same derived value (`"\(context.panelRoute)/ws"`) where needed in setup templates.
  - Updated:
    - `Sources/Deployer/Commands/System/SystemPaths.swift`
    - `Sources/Deployer/Commands/Setup/Templates/DeployerTemplate.swift`
    - `Sources/Deployer/Commands/Setup/Templates/NginxTemplate.swift`
  - Verified with a successful `swift build`.
- **3.24 discarded (`hexadecimalData` relocation):**
  - Removed the `App/Extensions.swift` organization note about `hexadecimalData` placement as not necessary to action right now.
  - Updated:
    - `review.md`
- **3.3 addressed (shared user-existence helper):**
  - Added `UserAccount.exists(_:)` and replaced duplicated `id -u` checks across setup/remove steps, preserving behavior while removing repeated helpers.
  - Added:
    - `Sources/Deployer/Commands/System/Shared/UserAccount.swift` (`exists`)
  - Updated:
    - `Sources/Deployer/Commands/Setup/Steps/PreflightStep.swift`
    - `Sources/Deployer/Commands/Setup/Steps/ServiceUserStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/StopServicesStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveServiceFilesStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveUserStep.swift`
  - Verified with a successful `swift build`.
- **3.5 addressed (shared trimmed text-file reader):**
  - Added `ConfigDiscovery.readTrimmedTextFile(at:)` and reused it for all `.version` readers while preserving environment-variable precedence in `DeployerReleaseAssets.localReleaseTag`.
  - Updated:
    - `Sources/Deployer/Commands/System/Shared/ConfigDiscovery.swift`
    - `Sources/Deployer/Commands/Version/DeployerVersion.swift`
    - `Sources/Deployer/Commands/Update/Steps/DownloadStep.swift`
    - `Sources/Deployer/Commands/System/Shared/DeployerReleaseAssets.swift`
  - Verified with a successful `swift build`.
- **3.7 addressed (single shell-quoting implementation):**
  - Kept `String.shellQuoted` as the canonical implementation and removed the now-redundant `TemplateEscaping.shellLiteral` wrapper, preserving exact quoting behavior while simplifying call sites.
  - Updated:
    - `Sources/Deployer/Commands/Setup/Templates/TemplateEscaping.swift`
    - `Sources/Deployer/Commands/Setup/Templates/DeployerctlTemplate.swift`
  - Verified with a successful `swift build`.
- **3.6 addressed (shared path normalization/comparison helper):**
  - Added `PathComparison` under shared command utilities and reused it for path-equality and standardized-path normalization previously duplicated across setup/runtime code.
  - Added:
    - `Sources/Deployer/Commands/System/Shared/PathComparison.swift`
  - Updated:
    - `Sources/Deployer/Commands/Setup/Steps/StageDeployerStep.swift`
    - `Sources/Deployer/App/Bootstrap.swift`
    - `Sources/Deployer/App/Configuration.swift`
  - Verified with a successful `swift build`.
- **3.8 addressed (shared terminal-width detection):**
  - Added `TerminalWidth.current()` with a hardcoded `[40, 100]` clamp and reused it across command console and deployment streaming output.
  - Added:
    - `Sources/Deployer/Commands/System/Shared/TerminalWidth.swift`
  - Updated:
    - `Sources/Deployer/Commands/System/Console/ConsoleSection.swift`
    - `Sources/Deployer/Deployment/Shell.swift`
  - Verified with a successful `swift build`.
- **3.4 addressed (shared stable-status wait helper):**
  - Added `ServiceManager.waitForStableStatus(product:)` and removed duplicated transient-state polling loops from update command/step code.
  - Updated:
    - `Sources/Deployer/Service/ServiceManager.swift`
    - `Sources/Deployer/Commands/Update/Steps/StartServiceStep.swift`
    - `Sources/Deployer/Commands/Update/UpdateCommand.swift`
  - Verified with a successful `swift build`.
- **3.19 addressed (shared backup-restore helper in update command):**
  - Kept backup restoration logic in one place by introducing `UpdateCommand.restoreBackupBinary(...)` and reusing it from both rollback paths (`UpdateCommand.rollback` and `ActivateReleaseStep`).
  - Updated:
    - `Sources/Deployer/Commands/Update/UpdateCommand.swift`
    - `Sources/Deployer/Commands/Update/Steps/ActivateReleaseStep.swift`
  - Verified with a successful `swift build`.
- **3.12 addressed (shared GitHub API error typing):**
  - Replaced command-specific `SetupCommand.Error.githubAPI(...)` throws from shared `GitHubAPI` with a dedicated `GitHubAPI.Error` (`requestFailed`, `invalidURL`) to keep error ownership in shared infrastructure.
  - Updated:
    - `Sources/Deployer/Commands/System/Shared/GitHubAPI.swift`
  - Verified with a successful `swift build`.
- **3.9 addressed (service-manager setup/teardown abstraction):**
  - Added `ServiceConfigurator` to consolidate setup/remove-time service-manager behavior and removed duplicated systemd/supervisor branching across setup/remove steps.
  - Added:
    - `Sources/Deployer/Service/ServiceConfigurator/ServiceConfigurator.swift`
    - `Sources/Deployer/Service/ServiceConfigurator/SystemdConfigurator.swift`
    - `Sources/Deployer/Service/ServiceConfigurator/SupervisorConfigurator.swift`
  - Updated:
    - `Sources/Deployer/Commands/Setup/Steps/RuntimeConfigStep.swift`
    - `Sources/Deployer/Commands/Setup/Steps/StartServicesStep.swift`
    - `Sources/Deployer/Commands/Setup/Steps/HealthStep.swift`
    - `Sources/Deployer/Commands/Setup/Steps/CleanupOrphansStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/StopServicesStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveServiceFilesStep.swift`
  - Verified with a successful `swift build`.
- **3.10 addressed (service-file teardown path centralization):**
  - Consolidated systemd/supervisor teardown path ownership in `ServiceConfigurator.removeConfigs(for:)`, removing duplicate remove-path maintenance across setup/remove/orphan-cleanup steps.
  - Updated:
    - `Sources/Deployer/Service/ServiceConfigurator/SystemdConfigurator.swift`
    - `Sources/Deployer/Service/ServiceConfigurator/SupervisorConfigurator.swift`
    - `Sources/Deployer/Commands/Setup/Steps/RuntimeConfigStep.swift`
    - `Sources/Deployer/Commands/Setup/Steps/CleanupOrphansStep.swift`
    - `Sources/Deployer/Commands/Remove/Steps/RemoveServiceFilesStep.swift`
  - Verified with a successful `swift build`.
- **3.11 addressed (shared release archive download/extract helper):**
  - Added `DeployerReleaseAssets.downloadRelease(...)` and `DeployerReleasePayload` to centralize the repeated latest-release archive download/extract/asset-validation path without merging setup-specific source-selection behavior.
  - Updated:
    - `Sources/Deployer/Commands/System/Shared/DeployerReleaseAssets.swift`
    - `Sources/Deployer/Commands/Setup/Steps/StageDeployerStep.swift`
    - `Sources/Deployer/Commands/Update/Steps/DownloadStep.swift`
  - Verified with a successful `swift build`.
- **3.13 addressed (remove false path polymorphism from update):**
  - Kept setup/remove on `SystemPaths` and update on executable-URL-derived paths, but removed the fake `SystemContext` conformance and unused `paths` placeholder from `UpdateContext`.
  - Updated:
    - `Sources/Deployer/Commands/Update/UpdateContext.swift`
    - `Sources/Deployer/Commands/Update/UpdateStep.swift`
  - Verified with static scans showing no update use of `SystemContext`, `paths`, or `SystemShell`, plus a successful `swift build`.
- **2.5 addressed (deployerctl internal duplication):**
  - Deduplicated the identity bridge in the `deployerctl` script template. Hoisted `ensure_user_manager` and `as_service_user` above the early-exit actions, extracted `resolve_service_identity`, and replaced the inline `update` and main-path blocks with function calls.
  - Updated:
    - `Sources/Deployer/Commands/Setup/Templates/DeployerctlTemplate.swift`
  - Verified with a successful `swift build`.

