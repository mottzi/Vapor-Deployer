# Deployment status is lifecycle; tests are audits

A Deployment's `status` reflects only its **deployment-lifecycle** state — never the outcome of a test run on its own. Test runs are split into two flavors with distinct semantics:

- **Manual test** (the row's Test action): a pure audit. It never alters `status`. The outcome is written to `lastTestOutcome` and appended as a labeled section to `output`, surfaced in the row's Tests column. A `.running` row whose manual tests fail stays `.running`; a `.pushed` row whose manual tests pass stays `.pushed`.
- **Inline pipeline test** (when `target.testing` is true): a phase of the deploy pipeline, not an audit. It owns `status` while in flight (`.testing`) and a failure produces `.failed` — because the **pipeline** failed, and the test phase happened to be the one that failed. The phase distinction stays in `lastTestOutcome` (false ⇒ tests were the failing phase) and the transcript, exactly as before.

The previous model treated `status` as "outcome of the most recent operation against this commit." Under that rule, clicking the Test action on a live `.running` deployment moved the row to `.tested` on pass or `.failed` on fail — a manual audit had the power to demote the live deployment in the UI, with no signal that the binary itself was untouched. The symmetric problem existed for `.built` rows. Users read this as a regression caused by their own audit, which is exactly backwards from what an audit should communicate.

The new model splits the two axes cleanly: lifecycle on the status pill, test verdict in a parallel Tests column driven by `lastTestOutcome`. A row can independently say "live and tests are currently failing against this commit" — which is the truth, and which the old model could not express.

The alternatives considered and rejected:

- **Make inline pipeline tests also audit-only.** Would require removing `.testing` as a status and silently continuing the pipeline regardless of test outcome, or inventing a new failure state. Inline test failure is a real pipeline failure — the build never happened, the deployment never advanced. Encoding that as anything other than `.failed` would mislead the user about what actually occurred.
- **Keep `.tested` as a status but block the Test action on `.running` / `.built` rows.** Reintroduces the eligibility-gate complexity that `lastTestOutcome`'s permissive design exists to avoid (env drift means the user must always be allowed to re-run any action). And it still leaves `.failed` rows getting flipped to `.tested` by a passing manual test, which is the same conflation in a different corner.
- **Surface the test outcome only in the transcript.** Hides the audit behind a click and makes the Test action feel like it had no effect. The whole point of running the audit is to see the verdict at a glance.

The cost accepted: `lastTestOutcome` is now load-bearing for the UI (previously an optimization + phase marker only); the `.tested` enum case is deleted; the Tests column is a new piece of UI surface to maintain. The DB is pruned rather than migrated — pre-existing `.tested` rows do not survive the cut.

If the deployer ever grows a per-deployment "verified" or "approved" concept that the user explicitly toggles, that belongs in its own field next to `lastTestOutcome`, not back in `status`. Status stays lifecycle-only.
