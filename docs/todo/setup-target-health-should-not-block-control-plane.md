# Setup Should Not Abort Control-Plane Installation When Target App Env Is Missing

Status: open.

## Summary

`deployer setup` currently treats the managed target app's health check as a hard setup gate. If the target app crashes because it expects environment variables that are not present yet, setup aborts before later control-plane steps run. This leaves the host in an awkward partial-install state: the Deployer service may be healthy, but `deployerctl` is not installed and the GitHub webhook is not created.

This is a product bug. A target app can legitimately require `.env` values before it can boot. That should not prevent Deployer's operator surface from being installed.

## Incident

During a reinstall test, the target app required `TEST_1` and `TEST_2`. The app loaded `.env` from its working directory, but the file was missing at first. The app service therefore crash-looped with:

```text
Vapor.Application.VariableError.variableNotFound
```

`HealthStep` successfully verified the Deployer service and port `8081`, then failed waiting for the app on `127.0.0.1:8080`. Because `HealthStep` throws, setup stopped before:

- `NginxStep`
- `TLSStep`
- `DeployerctlStep`
- `WebhookStep`
- `SSHHardeningStep`
- `SummaryStep`

The confusing result was that Deployer itself was running, but `/usr/local/sbin/deployerctl` did not exist and no GitHub webhook was present.

## Root Cause

`SetupCommand` orders `HealthStep` before installation of the operator wrapper and webhook provisioning, and `HealthStep` treats both Deployer health and target-app health as equally fatal.

That is the wrong boundary. Deployer health is a control-plane requirement. Target-app health is a managed-workload state. A failed workload should be surfaced clearly, but it should not prevent installing the tools needed to inspect, restart, or repair it.

## Desired Behavior

- Deployer service health remains a hard setup requirement.
- Target app service/port health becomes a warning or degraded setup outcome.
- Setup continues to install `deployerctl`, configure Nginx/TLS where possible, and sync/create the webhook when Deployer itself is healthy.
- The final summary must explicitly report target-app health failure and next commands, for example:

```text
Deployer installed successfully.
Managed app did not pass health checks.
Fix /home/<service-user>/apps/<app>/.env or app configuration, then run:
  sudo deployerctl restart app
  sudo deployerctl status app
```

## Design Notes

- The target app `.env` source of truth is documented in `docs/adr/0008-target-env-vars-are-a-plain-dotenv-file.md`.
- Setup should not create or overwrite `.env`; the ADR intentionally keeps setup out of target env management.
- Do not hide the failure. The setup output should be loud and actionable, but non-fatal for control-plane completion.
- Be careful with TLS/Nginx behavior: if app upstream health is missing, proxy config can still be written, but summary should say the app route will return upstream errors until the app starts.
- Webhook creation should not depend on the target app currently booting. Webhooks create future deployment events; app health is a separate runtime concern.

## Acceptance Criteria

- A target app that crashes on missing env vars no longer prevents `deployerctl` installation.
- A target app that crashes on missing env vars no longer prevents GitHub webhook setup.
- Setup exits successfully or with a distinct degraded outcome only after the control plane is usable.
- Final setup output names the failed target-app health check and gives exact remediation commands.
- Deployer health failures still abort setup.

