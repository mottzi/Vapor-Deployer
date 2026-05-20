# Drop client-side row reordering — server order is now the source of truth

With deployment rows sorted by the immutable `created_at` column, the Mist `sortable-collection` client-side reorder loop on the deployments table became redundant. Removing it simplifies the rendering path and eliminates a 1s reshuffle delay on every DOM mutation.

**What changed:**

- **`mist-behavior="sortable-collection"` removed from the deployments `<table>`,** along with its `data-mist-sort-order`, `data-mist-sort-type`, and `data-mist-sort-delay-ms` attributes.
- **`data-mist-sort-value` removed from each `DeploymentRow` `<tbody>`,** and the now-unused `createdAtUnixMs` computed property dropped from `Deployment`.
- **Insert order is preserved structurally.** New rows arrive via `mist-insert-position="afterend"` on the `<thead>`, which places each new component immediately below the header row — i.e. at the top of the list — and since `created_at` is monotonically increasing for new inserts, that position is always the correct sorted position. No client-side fix-up needed.
