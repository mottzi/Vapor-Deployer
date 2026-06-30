## Unreleased

- Add `deployerctl` deployment controls: list deployments by short SHA, deploy, build, run saved binaries, test, inspect output, delete rows, and remove saved binaries.
- Share one deployment engine between the panel and CLI, with cross-process operation locking so panel and CLI actions cannot run concurrently.
- Stream CLI-origin deployment progress back into the live panel through Mist-backed operation events, while keeping CLI deploys usable when the server is offline.
- Show short commit SHAs consistently in deployment rows and protect live rows from unsafe build, run, delete, and saved-binary removal actions.
- Persist setup toolchain paths in `deployer.json` so panel and CLI builds/tests use the same Swift environment.
- Continue setup when the target app fails health checks, keeping Deployer health fatal while installing `deployerctl`, Nginx/TLS, and GitHub webhook support before reporting workload remediation commands.
- Preserve existing install mode, deployment mode, and testing defaults when rerunning setup, and clarify when `deployerBranch` is ignored on binary installs.
- Refresh the root-owned `deployerctl` wrapper during successful self-updates by invoking the newly activated binary's embedded templates after the deployer service restarts.
- Persist the new deployer version marker before restarting during self-update, while restoring the previous marker on rollback so the panel metadata strip boots with the correct SHA.
- Install a narrow root helper and sudoers rule during setup/root refresh so panel-triggered updates from the service user can refresh only `/usr/local/sbin/deployerctl` and `/etc/deployer/deployerctl.conf`.
- Preserve existing deployerctl metadata while refreshing operational values from `deployer.json`, and keep existing installations safe by warning when a one-time root refresh is still needed to bootstrap the panel update helper.
