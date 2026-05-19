# Vapor-Deployer Context

## Domain Terms

- **Target app**: The user's Vapor application that the deployer builds, deploys, and supervises. Distinct from the deployer itself.
- **Deployment**: A repo snapshot (commit) that the deployer can test, build, and run. Persisted as a `Deployment` row. Operations against it are driven by the `Queue` actor.
- **Queue**: Actor that serializes target-app work (deploy, save-binary, restore-binary, test). Holds `isDeploying` as its lock.
- **Test run**: Executing `swift test` against a Deployment's commit. Runs inline before `swift build` in the deploy pipeline when `target.testing` is true, or on demand via the row's Test action (gated on `!hasSavedBinary`, same as Save-binary). A manual test run lands the row in `.tested` or `.testFailed`. An inline test failure aborts the pipeline and lands the row in `.testFailed` (analogous to how a build failure lands in `.failed`). Test runs use a `.build-tests/` scratch directory in the target, isolated from `.build/` — see [ADR 0003](docs/adr/0003-test-scratch-path-isolates-build-cache.md).
- **Deployment status semantics**: A Deployment's `status` reflects the outcome of its most recent operation; the full audit trail of every operation that has streamed against it lives in `output`. Statuses do not preserve worst-case history — clicking Test on a `.failed` row and getting a pass moves the row to `.tested`, with the earlier build-failure transcript still present in `output`.
- **Self-update**: Replacing the deployer's own binary (and, for source installs, its checkout) with the latest release, then restarting the deployer service. Distinct from a target-app deployment.
- **Updater**: The primitive that owns the self-update lock and drives the self-update lifecycle.
- **DeployerPhase**: Derived display state computed from Queue + Updater locks. One of `ready`, `deploying`, `updating`. Used by the panel to render the runtime badge.
- **DeployerStatus**: The Mist fragment component that renders the runtime-bar badge and owns the self-update action. Backed by a `LiveState<DeployerPhase>` shared between `Queue` and `Updater`.
- **Panel**: The web dashboard served by the deployer service, rendered with Leaf and updated live via Mist.
