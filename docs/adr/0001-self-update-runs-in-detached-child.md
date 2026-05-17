# Self-update runs in a detached child process

Triggering a deployer self-update from the panel cannot run in-process: the update pipeline includes `StopServiceStep`, which calls `systemctl --user stop deployer` (or `supervisorctl stop deployer`) — the deployer would kill its own caller mid-flight, defeating the rollback path that depends on explicit stop/start.

We launch `deployer update` as a detached child that escapes the deployer service's process group / cgroup, so it survives the parent's death:

- **systemd**: `systemd-run --user --collect --unit=deployer-self-update-<uuid>` — transient service unit owned by the user manager, separate cgroup. Output goes to the user journal under that unit name.
- **supervisor**: `setsid <bin> update` — `stopasgroup=false` is supervisor's default, so SIGTERM to the deployer pid does not propagate to the new session. Inherited fds route output to the deployer log via supervisor's existing `stdout_logfile` redirect.

The Mist `UpdateAction` returns `.success` immediately after spawning. The full `UpdateCommand` pipeline (including rollback semantics) is reused without modification. The child writes a completion sentinel file (`DEPLOYER_COMPLETION_SENTINEL`) on **every** exit — success, early failure, and rollback alike. A background `Task` in the `Updater` actor polls for that sentinel every 2 s; when found, it clears `isUpdating` and broadcasts `.ready` back to panel clients. If the child kills the parent before writing the sentinel (the normal late-success / late-failure-rollback paths), the watcher `Task` dies with the process and the next boot starts fresh with `isUpdating = false`.

Rejected alternative: running the steps in-process and relying on the service manager's autorestart after the binary swap. Rejected because the rollback path requires explicit stop/start to be observable, and an autorestart-only design loses that observability.
