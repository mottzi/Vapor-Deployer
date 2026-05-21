# Automatic deployments resume after restart

In automatic mode, a push that arrives while a deployment or self-update is already in progress is queued as canceled rather than built immediately. If the deployer then restarts before it gets to drain that queue — due to a self-update completing, a host reboot, or a service restart — those pushes were left stranded. They showed up in the panel but required a manual redeploy to actually build.

The deployer now picks up where it left off on every boot.

**What changed:**

- On startup, the deployer checks for stranded canceled deployments. If any are found, it automatically picks up the newest one and starts the build pipeline — exactly as if the push had just arrived.
- If a new push arrives while the boot-drain build is still in progress, the queue drains it next in the normal way. No pushes are lost.
- If a newer successful deployment already ran before the restart (e.g. via a manual redeploy from the panel), the stranded row is recognized as superseded and skipped. The deployer does not revert work that has already been done.
- This only applies in automatic deployment mode. In manual mode the deployer continues to wait for explicit action.
