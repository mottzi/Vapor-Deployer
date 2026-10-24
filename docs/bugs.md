# Known bugs

## Source-update rollback does not restore the checkout revision

### Status

Open.

### Affected path

Self-updates for installations configured with `buildFromSource: true`.

### Description

`SourceUpdateStep` records the current checkout revision and then hard-resets the installed Deployer checkout to `origin/<deployerBranch>` before building the candidate executable. If activation or restart subsequently fails, `UpdateRollback` restores the previous executable, `Public`, `Resources`, and version marker, but it does not restore the checkout to its previous Git revision.

The installation can therefore enter a split state:

```text
checkout HEAD       = failed new revision
running executable  = restored previous revision
version marker      = restored previous revision
```

On the next source update, `SourceUpdateStep` compares checkout `HEAD` before and after resetting to the remote branch. Because the checkout already points at the failed new revision, both values are equal and the update is reported as up to date. The candidate is not rebuilt or activated, so the restored old executable can remain active indefinitely even though the checkout is current.

### Operational impact

- A failed source update cannot necessarily be retried without another remote commit or manual checkout repair.
- The running executable can diverge from the installed checkout and its `Package.resolved` dependency graph.
- Embedded Mist assets remain internally consistent with whichever executable is running, but after rollback they may be older than the checkout-selected Mist revision.

### Expected resolution

Treat the checkout revision as part of the source-update transaction. Capture the previous full Git revision before reset and restore it during rollback, or determine update eligibility from the installed version marker rather than checkout equality. A fix must also ensure that a previously failed revision can be rebuilt and retried without requiring a new upstream commit.

### Relevant implementation

- `Sources/Deployer/Commands/Update/Steps/SourceUpdateStep.swift`
- `Sources/Deployer/Commands/Update/UpdateRollback.swift`

