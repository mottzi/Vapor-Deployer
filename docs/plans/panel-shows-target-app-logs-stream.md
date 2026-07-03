# Panel Shows Target App Logs Stream

Living feature specification for adding a target application logs page to the Vapor-Deployer web panel.

## Status

Draft. This document captures the core feature and the current grill queue. Secondary log tools such as download, filtering, search, highlighting, or historical archives are intentionally out of scope for this file unless promoted into the core feature later; each should get its own plan file.

## Source Context

- User-provided seed spec: `/Users/berken/Library/Mobile Documents/com~apple~CloudDocs/Downloads/deployer-app-logs-spec.md`
- Prior repository plan for comparison: `docs/plans/gemini-panel-shows-target-app-logs-stream.md`
- Panel routes and auth: `Sources/Deployer/Panel/Panel.swift`
- Settings page implementation and template: `Sources/Deployer/Panel/Settings.swift`, `Resources/Views/Deployer/DeployerSettings.leaf`, `Public/deployer/styles/settings.css`
- Current live operation output stream: `Sources/Deployer/Operation/OperationEvent/OperationOutputStream.swift`, `Resources/Views/Deployer/DeploymentRow.leaf`, `Public/deployer/styles/output.css`
- Shell streaming primitives: `Sources/Deployer/Shell/Shell+Streaming.swift`, `Sources/Deployer/Shell/Shell+StreamingTail.swift`
- Mist client stream implementation: `Public/deployer/mist.js`
- Mist server stream/subscription implementation: `/Users/berken/Development/Swift/Vapor-Mist/Sources/Mist/Delivery/Streams.swift`, `/Users/berken/Development/Swift/Vapor-Mist/Sources/Mist/Clients/Clients+Registration.swift`, `/Users/berken/Development/Swift/Vapor-Mist/Sources/Mist/Delivery/Socket.swift`

## Goal

Authenticated panel users can open a dedicated Logs page for the configured target app and watch the target app log file stream in real time from the browser.

The feature exists to answer the immediate operational question: "What is my deployed app doing right now?" It should avoid forcing the user to SSH into the server and run a tail command just to inspect stdout/stderr after a deployment, restart, request, or failure.

## Non-Goals

- Do not build a general log analytics product.
- Do not persist a separate copy of app logs in the Deployer database.
- Do not stream logs while nobody is subscribed to the logs page.
- Do not put download/search/filter/highlighting/pause controls in this core spec unless explicitly promoted. Those are plausible follow-up specs.
- Do not replace the deployment-operation output stream. Operation logs and target app runtime logs are separate concepts.

## User Experience

### Entry Point

The main panel target app actions section gets a new `Logs` button next to the existing `Settings` button.

Current placement pattern:

- `Resources/Views/Deployer/DeployerPanel.leaf` renders a static Settings link inside the `TargetStatusActions` Mist container, but outside the Mist-managed component, so status action rerenders do not replace it.
- The Logs link should follow the same pattern and styling family.

Expected behavior:

- Clicking `Logs` opens an authenticated route under the configured panel route, expected as `GET {panelRoute}/logs`.
- The button is visible independently of whether the target service is currently running. A stopped app can still have useful prior logs.
- On small viewports, the button should collapse consistently with the target action toolbar behavior.

### Logs Page

The Logs page should be visually and structurally a sibling of the Settings page:

- Same shell, workspace, target panel, runtime bar, session bar, Back link, and Sign out treatment.
- Same CSS layout foundation as `DeployerSettings.leaf`.
- Page title should communicate `Logs`.
- Context strip should include target name and resolved log file path.
- Instead of the Settings key/value form body, the page body shows a console-style log stream.

The console should reuse the current deployment output console visual language where appropriate:

- `dp-output-pre` / `dp-output-pre--live` are already used for live operation output.
- The live target app log console likely needs page-specific wrapper sizing, but should not invent a disconnected terminal style.
- Empty state should be quiet and useful, for example "Waiting for logs..." or "No log output yet." Exact copy is unresolved.

### Stream Behavior

The initial page load should show a bounded tail of recent log content, then append new output as it arrives.

Required behavior:

- The tailer starts only when at least one active logs subscriber exists.
- The tailer stops when the last active logs subscriber leaves.
- Multiple open Logs pages share one tail process / tailing task for the target app.
- The Logs button is always visible in v1, even when the target app is stopped.
- The page includes a `Clear` button in v1. It clears only the current browser's visible/current buffered log view and does not truncate the server log file or stop the shared stream producer.
- The client auto-scrolls when it is already at the bottom.
- If the user has scrolled upward, new log lines should not yank the viewport down. This mirrors the desired behavior of the deployment row output stream.
- The browser DOM and client-side stream buffer must be bounded in v1 so a tab left open indefinitely does not grow until it crashes.

## Backend Requirements

### Log File Path

The target app log file path is resolved from the existing setup templates:

```swift
"\(config.target.directory)/deploy/\(config.target.name).log"
```

Rationale:

- `SystemdTemplate.appUnit` writes stdout and stderr to `StandardOutput=append:{deployDir}/{product}.log` and `StandardError=append:{deployDir}/{product}.log`.
- `SupervisorTemplate.appProgram` writes app stdout to the same `{deployDir}/{product}.log` with stderr redirected.
- This should become a single named property, likely on `Configuration` or `TargetConfiguration`, so panel rendering and tailer setup do not duplicate path construction.

### Tailing

The implementation should use one subscriber-aware target app log tail service, not a new process per browser tab.

Candidate behavior:

- On first active subscriber, start `tail -n 50 -F {logFilePath}`.
- On last subscriber, terminate the tail process/task and clear live resources.
- `tail -F` is preferred for the core spec because the existing service templates append to a file that can be recreated, truncated, or rotated.
- Output should be sanitized consistently with `OperationOutputStream.stripAnsi(_:)` before reaching the browser and server-side Mist buffers.
- Tail process stderr should be handled. If `tail` cannot open the file yet, the Logs page should behave like the deployment row stream UI: the console remains present with a quiet waiting/empty state rather than the route failing.
- The initial tail count is a fixed v1 product decision: 50 lines. Making it configurable can be considered later if a real user need appears.

### Mist Integration

This feature should be implemented as a proper Mist component/stream integration rather than bespoke WebSocket code.

Current relevant Mist behavior:

- `Streams` are append-only text content scoped to a component instance and replayed to new subscribers.
- `Streams.append` stores the full accumulated text in a server-side buffer and broadcasts an append message.
- The client also stores full stream text in `streamBuffers` so streams can be restored after component morphs.
- Component subscriptions are tracked by component name in `Clients`.
- Mist does not currently expose a public subscriber-count callback/hook for Deployer to start and stop external producers.

Required Mist capability:

- Deployer needs a public way to know when active subscribers for the logs component transition from zero to nonzero and nonzero to zero.
- This should be a reusable Mist subscription lifecycle feature, not a Deployer-only workaround.
- The API should support Deployer's needs first, while being shaped as a generally useful Mist feature because external stream producers are common beyond Deployer.
- Mist should own a static stream concept so global streams do not need sentinel UUIDs.
- Mist should support subscriber-driven stream producers: start work when the relevant stream/component gains its first subscriber, and stop work when it loses its last subscriber.

Likely component shape:

- A static logs component, for example `TargetAppLogs`.
- The app log should use a Mist static stream, not an instance stream with a sentinel UUID.
- The static stream should still have a stable component/stream identity so the client can declaratively subscribe and restore content across reconnects.

## Client Requirements

### Generic Buffer Pruning

The browser memory issue is generic to Mist streams, not unique to the target app logs page.

Recommendation:

- Add a generic Mist client attribute such as `data-mist-stream-limit` to stream targets.
- `mist.js` should prune both the target DOM and its matching `streamBuffers` entry according to that limit.
- The limit should be opt-in per stream target so short operation logs can keep their full current behavior unless configured, though long-lived streams should opt in.
- Bounded stream memory is v1 scope for this feature, not a later enhancement.
- Crash prevention must cover both client and server. Mist's server-side stream buffers must also be bounded for long-lived/static streams.

Candidate markup:

```html
<pre
  class="dp-output-pre dp-output-pre--live dp-app-log-console"
  mist-stream="app-log"
  data-mist-stream-limit="1000"
></pre>
```

Open design details:

- The public stream limit should be line-based because logs are read as lines and text chunks do not necessarily align with WebSocket message chunks.
- Mist should also include an internal byte safety cap so pathological single-line logs cannot exhaust memory.
- Mist should preserve the latest content after pruning, including across `restoreStreams()`.
- Pruning must not break HTML escaping. Current `appendChild(document.createTextNode(text))` is good because it treats logs as text, not HTML.

### Auto-Scroll

Current `mist.js` always calls `scrollStreamTargetToBottom(target)` after append or replace.

Required refinement:

- Auto-scroll only if the stream target was at or near the bottom before the append.
- If the user scrolls up, leave scroll position stable.
- When the user returns to the bottom, resume automatic following.

This behavior should be generic in Mist stream handling if possible, because deployment row live output and app logs both want it.

## Security and Privacy

- The logs route must use the existing `PanelAuthenticator`.
- The WebSocket stream must stay protected by the current session-authenticated Mist socket upgrade.
- The page must not expose the log route or stream to unauthenticated clients.
- Log content must be inserted as text, never as unsafe HTML.
- ANSI/control-sequence stripping should be shared or made reusable from the current operation-output path.
- App logs should strip ANSI/control sequences in v1. ANSI-to-color rendering is a separate richer terminal feature.
- Tail process errors should use the better user experience for the situation: user-actionable or persistent failures can be surfaced in the console, while transient expected `tail -F` waiting conditions should stay quiet and be logged by Deployer as needed.
- The feature may expose secrets if the target app logs secrets. That is inherent to showing app logs; the spec should avoid adding extra sharing/download surfaces in the core feature.

## Reuse and DRY Candidates

- Sibling route and context pattern from `Settings.swift`.
- Shared Settings page layout and CSS primitives from `DeployerSettings.leaf` and `settings.css`.
- Console styling from `output.css`.
- ANSI stripping from `OperationOutputStream`.
- Ordered process output capture ideas from `Shell+Streaming.swift`.
- Tail/rolling-window concepts from `Shell+StreamingTail.swift`, while recognizing that page streaming needs a long-lived subscriber-aware process rather than a command that exits.
- Mist component registration and stream delivery rather than adding a second WebSocket system.

## Acceptance Criteria

- Main panel shows a `Logs` button next to `Settings`.
- `GET {panelRoute}/logs` renders for authenticated users and redirects unauthenticated users to login.
- The Logs page matches the Settings page shell and toolbar structure.
- The page shows a console stream for the target app log file at `{target.directory}/deploy/{target.name}.log`.
- No tail process/task is running when zero Logs page subscribers are active.
- Exactly one shared tail producer runs when one or more Logs page subscribers are active.
- New subscribers receive an initial bounded tail and then live appended output.
- Closing/navigating away from the last Logs page stops tailing.
- Browser-side log content is bounded.
- App output cannot inject HTML/script into the page.
- Existing deployment row operation output behavior does not regress.

## Grill Queue

### Round 1: Core Boundaries

1. Resolved: v1 uses a fixed initial tail of 50 lines.
2. Resolved: if the log file does not exist yet, the page behaves like the deployment row stream UI and keeps the console in a waiting/empty state.
3. Resolved: Logs is always visible in v1, even when the target app is stopped.
4. Resolved: bounded client memory / OOM prevention is v1 scope.
5. Resolved: v1 includes a Clear button for the current browser buffer only.

### Round 2: Mist Contract

1. Resolved: require a reusable Mist subscription lifecycle feature rather than a Deployer-specific subscriber-count poll.
2. Resolved: Mist should grow static streams; app logs should not use a sentinel UUID.
3. Resolved: the public stream limit is line-based, with an internal byte safety cap for pathological lines.
4. Resolved: bounded stream buffers are required on both client and server.
5. Open: should the same generic auto-scroll refinement be applied to deployment operation streams immediately?

### Round 3: Operational Semantics

1. Should the tailer run `tail -n N -F`, or should Deployer implement native file watching?
2. Resolved: tail errors should follow the better UX path; expected waiting stays quiet, actionable/persistent failures may surface in the console and Deployer log.
3. Resolved: strip ANSI/control sequences in v1.
4. What is the expected behavior across log rotation/truncation/restart?

### Round 4: Follow-Up Specs

If any of these are desired, create separate plan files:

- Download full log file.
- Search/filter within the current browser buffer.
- Pause/resume stream rendering.
- Severity highlighting.
- Copy visible logs.
- Multi-file logs or deployer service logs.

## Current Recommendation

For the specific pruning dilemma: extend Mist's generic stream client behavior with an opt-in attribute, likely `data-mist-stream-limit`, rather than writing page-specific JavaScript in the Logs view.

Reasoning:

- The current memory leak risk exists in `mist.js` stream buffers and DOM appends, not only in this page.
- Deployment operation output already uses `mist-stream="operation-log"` and benefits from the same bounded-stream mechanics.
- Page-specific pruning would leave Mist's internal `streamBuffers` unbounded unless it reached into Mist internals, which is the wrong ownership boundary.
- A declarative attribute keeps the logs page simple and makes future long-lived streams safer by default when they opt in.
