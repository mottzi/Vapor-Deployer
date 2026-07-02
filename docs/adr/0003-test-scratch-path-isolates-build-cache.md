# `swift test` uses an isolated scratch path

`OperationWorker.test()` invokes `swift test -c <buildMode> --scratch-path .build-tests` against the target's working directory, instead of letting it default to the same `.build/` directory used by `swift build`. This applies to both the inline pipeline test step (when `target.testing` is true) and the manual Test action.

The reason is [SwiftPM bug #8031](https://github.com/swiftlang/swift-package-manager/issues/8031), open since October 2024 and still unfixed in Swift 6.3. `swift test` globally sets `buildParameters.enableTestability = true`, which adds `-enable-testing` to **every module in the dependency graph** — not just test targets. SwiftPM doesn't fingerprint the flag-set when keying its object-file outputs, so `swift test` and `swift build` write to the same paths (e.g. `.build/x86_64-unknown-linux-gnu/release/NIOPosix.build/BaseSocket.swift.o`) but with incompatible flags. Alternating between the two commands — which is exactly what the deploy pipeline does on every push — clobbers each other's cache and forces a full rebuild every iteration. Observed cost on a real target: ~20s incremental builds became ~900s.

Separate scratch paths sidestep the bug entirely: `.build/` stays under `swift build`'s exclusive ownership, `.build-tests/` stays under `swift test`'s. Each cache remains independently incremental. There is no flag-set-aware caching mode in SwiftPM and no signal one will be added soon (the proposed fix in #7904 stalled at the pitch stage).

The alternatives considered and rejected:

- **`--disable-testable-imports`** — Only works for targets whose tests don't use `@testable import`. We can't assume that across all target apps the deployer will ever manage.
- **`swift build --build-tests` single-pass** — Produces a binary tainted with `-enable-testing`. The SwiftPM docs explicitly warn against shipping such binaries: testability removes optimizations and exposes internals.
- **Per-target opt-in config flag for `--disable-testable-imports`** — More config surface, and leaves `@testable`-using targets stuck on the slow alternating-cache path anyway.
- **Drop inline pipeline testing, keep only manual runs** — Defeats the design goal of testing as an automatic pre-deploy gate.

The trade-off accepted: per-target disk usage roughly doubles (cache duplication for the dependency graph — measured at ~3-5 GB extra for a Vapor-scale target). The first test run on a fresh target is a full cold compile in the new scratch directory; every subsequent run is incremental. Disk is the cheapest resource here; correctness across all targets is the constraint.

This matches the pattern used by SwiftPM's own CI (`.github/workflows/pull_request.yml` invokes `swift-build --build-tests --scratch-path .tests` on Windows). It is the boring, correct answer.

If `--scratch-path` is ever removed or its semantics change in a future Swift release, or if SwiftPM ships flag-set-aware caching, this can be reverted to a single `.build/` directory with no behavior change for users.
