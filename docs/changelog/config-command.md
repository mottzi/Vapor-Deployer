# Edit `deployer.json` from the CLI without a setup re-run

Previously, changing any field in `deployer.json` — even a low-risk one like the target branch or whether tests run in the pipeline — meant either editing the file by hand and restarting the service yourself, or sitting through a full `deployerctl setup` re-run. The new `deployerctl config` command makes safe, in-place edits to a narrow set of fields a one-liner, with the same restart-safety guarantees as `deployerctl update`.

**What changed:**

- `sudo deployerctl config` (no arguments) prints the six fields you can edit and their current values:
  - `deployerBranch` — which branch `deployerctl update` pulls from (source installs only)
  - `target.branch` — which branch of the target app is deployed
  - `target.buildMode` — `debug` or `release`
  - `target.deploymentMode` — `automatic` or `manual`
  - `target.binaryBehaviour` — binary retention policy (`newest:5`, `automatic:500`, `all`, `off`)
  - `target.testing` — whether `swift test` runs in the deploy pipeline
- `sudo deployerctl config <field> <value>` validates the new value, writes `deployer.json` atomically, and prompts to restart the deployer service so the change takes effect. Answer **n** to defer the restart and apply the change at the next deployer restart.
- Before restarting, `deployerctl config` checks whether the deployer is mid-deploy or mid-update and refuses with a clear message rather than interrupting an in-flight operation — the same safety net `deployerctl update` uses.
- Every other field in `deployer.json` (the deployer port, the app port, nginx-related paths, the webhook secret, install directory, service manager, and so on) is **not** editable through this command. Those fields are entangled with files on disk (nginx config, systemd unit, target app checkout) that a JSON-only change would silently desynchronize. If you try to edit one, `deployerctl config` tells you to re-run `deployerctl setup` instead.
- Validation reuses the same checks the deployer runs at boot, so `deployerctl config` cannot leave the JSON in a state the deployer would refuse to load.

Run `sudo deployerctl config` to see your current values.
