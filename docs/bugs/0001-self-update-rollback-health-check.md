# Self-update rollback misses post-start crashes

## Status

Open...

## Summary

`deployer update` can report success after installing a bad deployer binary if the service manager briefly reports the service as `running` before the process crashes. In that case the old binary backup is left unused, the update is marked complete, and the panel may return `502 Bad Gateway` until a manual recovery update is run.

## Impact

- A panel-initiated self-update can leave the deployer web service down.
- The update command may print a successful completion message even though the new service crashes immediately after startup.
- Operators must recover through the CLI/control surface instead of relying on automatic rollback.

## Evidence

Observed during the updater polling startup-order regression: the update reached `StartServiceStep`, systemd reported `running`, and the command completed. Shortly afterward the new process crashed with `OperationCoordinator not initialized`, leaving nginx unable to reach the panel until a manual `deployerctl update` installed the follow-up fix.

The current rollback path only runs when `ActivateReleaseStep`, `PersistVersionStep`, or `StartServiceStep` throws. `StartServiceStep` calls `waitForStableStatus`, but `waitForStableStatus` returns as soon as it observes `.running`, so it does not catch crashes that occur just after the first successful status read.

## Likely Cause

The post-start verification is too shallow for self-updates. "The service reached running once" is not the same as "the new deployer is healthy enough to keep."

## Fix Direction

- Strengthen `StartServiceStep` verification with a short settling window.
- Prefer checking the local control endpoint after startup, since it proves the HTTP server, route registration, and control token path are alive.
- If post-start health fails, trigger the existing rollback path so the previous binary/assets/version marker are restored and restarted.
- Keep CLI recovery behavior: if the server is unreachable before an update starts, `deployer update` should still be allowed to proceed.
