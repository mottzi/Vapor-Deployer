# Safer self-updates: deploy and update no longer race

Running `deployer update` from the command line while a deployment was in progress (or vice versa) could previously cause both operations to run concurrently — leaving the target app in an inconsistent state or interrupting a deploy mid-build with an unexpected service restart.

**What changed:**

- `deployer update` now checks the running server's state before proceeding. If a deployment is in progress, the update refuses immediately with a clear message: *"Deployer is busy (phase: deploying). Wait for the current operation to finish, then retry."*
- Deployments now check whether an update is already running before starting. A `deployer update` in progress — whether launched from the CLI or the panel — blocks new deployments until the update completes.
- The panel's deployer status badge now reflects updates launched from the command line, not just ones triggered through the panel itself. The badge flips to **Updating** within ~2 seconds of any `deployer update` invocation.
- If the deployer service is not running when you invoke `deployer update` (the recovery scenario), the command proceeds as before — no change to that flow.
