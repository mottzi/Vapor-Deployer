# ADR 0011: Post-Deployment Health Probes and Auto-Rollback

## Status
Accepted

## Context
Deployer restarts the target service during promotion and assumes success if systemd/supervisor doesn't immediately report an exit error. If the app crashes 5 seconds later due to a database connection timeout or a missing environment variable, the dashboard still marks it as successfully running, causing silent production downtime. 

To ensure safety, we decided to verify target app functionality right after service startup using a health probe. If the check fails, the deployer will automatically roll back to the previously running version.

## Decision
1. **Trigger Scope**: Run the health probe for both manual and automatic promotions. If the probe fails, roll back to the **predecessor binary**. During the rollback execution itself, the health check is bypassed to prevent infinite loops. If the very first deployment of an app fails the health check, shut down the target service and leave it offline (as there is no prior stable state to restore).
2. **Protocol**: By default, perform a TCP port probe verifying that the target application successfully bound to its port. If the configuration parameter `target.healthCheckPath` is configured in `deployer.json` (e.g. `"/health"`), upgrade to an HTTP `GET` request. Any status code in the `200-399` range is treated as healthy.
3. **Thresholds & Settle check**: Mimic the self-update logic with a **10-second total timeout**, a **500ms poll interval**, and a **2-second settle duration**. The app must respond healthy continuously for at least 2 seconds before the promotion is declared successful.
4. **Lifecycle & UI Integration**: Keep the active deployment row in its transient lifecycle status (`.building` or `.restoring`) during the health check phase to avoid adding new database status states. Stream all probe attempts, success indicators, and rollback logs directly to the live terminal transcript in the panel.
5. **Emergency Bypass**: Add a `--skip-health-check` flag to `deployerctl deploy` and `deployerctl run` to allow emergency overrides. The web panel UI will not expose this flag in v1 to keep standard operations protected.
6. **Configuration Schema**: Expose these settings under the `target` configuration block in `deployer.json` (e.g. `target.healthCheckPath`, `target.healthCheckIntervalMs`).

## Consequences
* **Production Reliability**: Eliminates silent deployment failures due to runtime boot crashes.
* **Slightly Longer Deploys**: Successful deployments will take at least 2 seconds longer (due to the settle duration validation) to guarantee stability.
* **Deterministic Failures**: Failed builds due to boot-looping code will cleanly show as `.failed` with the failed probe attempts visible in their build output stream.
