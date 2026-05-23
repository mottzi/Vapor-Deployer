# Boot-drain replays the newest stranded canceled deployment on restart

## Context

When `Queue.recordPush` receives a push while `isDeploying` or `isUpdating` is true, automatic-mode pushes are written as `.canceled` rather than starting a build. This means any deployer downtime — self-update, host reboot, OOM kill, manual restart — leaves those pushes stranded: the queue was never running to drain them, and they accumulate until an admin manually redeploys from the panel.

This is a general "deployer was offline for a window" problem, not specific to self-update.

## Decision

On boot, the queue checks for stranded `.canceled` rows and picks up the newest one, starting the build pipeline exactly as if a fresh push had arrived.

**Design:**

- `Queue.drainOnBoot()` is gated on `deploymentMode == .automatic`. `.canceled` rows only originate from automatic-mode pushes, but they can survive in the DB across a mode switch; draining them in manual mode would violate the user's explicit control preference. The guard short-circuits before any DB query.
- `Queue.drainOnBoot()` queries for the newest `.canceled` row for the product (by `startedAt` descending), runs `isSuperseded` against it, and calls `deploy()` if it passes. No-ops if nothing is stranded or the candidate is already superseded by a newer successful deployment.
- Triggered at the end of `configurePanel`, after all Mist components are registered, so state broadcasts from the drain are visible to connected clients.
- Uses the same `deploy()` → `start()` path as normal operation. All existing guards apply: `isDeploying`, `isUpdating`, and the `UpdateLock` check. If the deployer restarted mid-update and the lock is still held, `drainOnBoot` silently no-ops.
- Only the newest `.canceled` row is used as the seed. Older stranded rows are left as-is — in automatic mode only the latest commit matters. If a new push arrives during the boot-drain build, `nextQueuedDeployment` picks it up naturally via the normal queue-drain loop.
- `bootDrainSeed` is a separate query from `nextQueuedDeployment`. The two have different contracts: `nextQueuedDeployment` anchors on a known timestamp and finds the next in a running chain; `bootDrainSeed` finds the newest across all time unconditionally.

## Consequences

Stranded `.canceled` deployments are automatically replayed on every restart. The admin no longer needs to manually redeploy after downtime. Superseded rows are skipped, so a manually-triggered restore or deploy that ran while the deployer was offline is respected and not overwritten.
