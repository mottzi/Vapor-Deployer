# Deployment row order now reflects commit arrival, not last build trigger

The deployments table previously sorted by `started_at`, which was overwritten every time `start()` actually began a build or restore. The practical consequence: triggering a re-deploy on an older `.pushed` row caused that row to leap to the top of the table, even though its commit was older than rows above it — so the visual order shuffled around as deployments finished or were re-triggered.

**What changed:**

- **New `created_at` column on `deployments`.** Auto-stamped at row creation via `@Timestamp(on: .create)`, immutable for the lifetime of the row.
- **Panel sorts by `created_at` descending.** Commit/arrival order is now stable — rows no longer jump when you click Deploy on an older pushed entry.
- **`started_at` keeps its build-anchor role.** Build duration (`finished_at - started_at`) and the superseded-deployment detection in `Queue+Execution` continue to work off the actual build-start timestamp, unchanged.
- **Backfill migration.** `AddCreatedAt` adds the column and seeds existing rows from `started_at` so historical ordering is preserved. The seeded first-deployment row is stamped with the commit's `committedAt`, matching its `started_at`/`finished_at`.
