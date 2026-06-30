## Unreleased

- Add `deployerctl` deployment controls: list deployments by short SHA, deploy, build, run saved binaries, test, inspect output, delete rows, and remove saved binaries.
- Share one deployment engine between the panel and CLI, with cross-process operation locking so panel and CLI actions cannot run concurrently.
- Stream CLI-origin deployment progress back into the live panel through Mist-backed operation events, while keeping CLI deploys usable when the server is offline.
- Show short commit SHAs consistently in deployment rows and protect live rows from unsafe build, run, delete, and saved-binary removal actions.
- Persist setup toolchain paths in `deployer.json` so panel and CLI builds/tests use the same Swift environment.
- Track a known setup issue where target-app health failures can abort setup before `deployerctl` and webhook installation.
- Preserve existing install mode, deployment mode, and testing defaults when rerunning setup, and clarify when `deployerBranch` is ignored on binary installs.
- Track a known update issue where `deployerctl` wrapper template changes are not refreshed by the self-update flow.
