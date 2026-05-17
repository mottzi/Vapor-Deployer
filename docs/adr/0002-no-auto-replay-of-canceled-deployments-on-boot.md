# No auto-replay of canceled deployments on boot

When a self-update is running, `Queue.recordPush` treats `updater.isUpdating` like `isDeploying` and writes incoming automatic-mode pushes as `.canceled` (manual-mode pushes still write `.pushed`). After the deployer restarts onto the new binary, those `.canceled` rows are *not* automatically picked up and built — the admin sees them in the panel and can redeploy manually.

This looks like a bug at first glance: in normal operation, `.canceled` rows in automatic mode are queued work that the running `Queue` actively drains via `nextQueuedDeployment`. The reason we don't drain them post-restart is that this isn't a self-update concern — it's a general "deployer was offline for a window" concern. The same gap exists today after host reboots, OOM kills, or any `deployerctl restart`. Special-casing self-update would encode a workaround for a missing general feature.

Boot-time replay of stranded `.canceled` rows is deferred as a separate feature, to be designed with its own scope: how far back to look, supersession checks against the live binary, multi-target handling, and what to do when the recovery deployment itself fails.

The deliberate decision here is: **the self-update PR preserves the existing mode contract (automatic → `.canceled`, manual → `.pushed`) and does not introduce special recovery behavior.** Future engineers tempted to "fix" the stranded rows during self-update should fix the general restart case instead.
