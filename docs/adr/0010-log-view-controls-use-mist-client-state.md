# Log view controls use Mist client state

The target app Logs page includes view-only controls such as line wrapping. These controls affect how one connected browser session reads the stream; they do not change the target app, the log source, the retained stream buffer, or any persisted deployer configuration.

Decision: log view controls use Mist per-client `ComponentState`, not browser `localStorage` and not Deployer persistence. `TargetAppLogs` declares `wrapDisabled` with a default of `false`, exposes a `toggleWrap` action, and renders the log `<pre>` with or without `dp-output-pre--nowrap` from the initiating client's state. Wrapping is enabled by default, toggling one browser session does not affect another session, and a reload/reconnect may return to the default because Mist client identity is WebSocket-session scoped.

This required a Mist framework change: successful actions on fragments with no model `targetID` now render and deliver the updated fragment back only to the initiating client. Instance actions keep their existing model-instance update path. The logs fragment opts into a state-aware manual render hook so the action-mutated state is visible during the post-action render. The Mist client also restores remembered stream text after fragment morphs, so toggling wrap changes the element class without clearing the visible log buffer.

This ADR exists because the visible feature is deceptively small. Without this context, the surprising part is why Deployer changed Mist instead of adding a local class toggle. The reason is that Deployer's panel treats Mist as the UI state boundary: server-rendered components own their rendered shape, Mist actions own state mutation, and per-client component state owns session-local view preferences.

Rejected alternatives:

- **Use `localStorage` and browser-only class toggling.** Rejected because Deployer's panel is intentionally Mist/server-rendered. A browser-only toggle would create a second UI state mechanism, duplicate component markup assumptions in JavaScript, and bypass the action/result semantics already used by panel controls.
- **Persist wrap preference in Deployer configuration or SQLite.** Rejected because wrapping is a viewing preference, not deployment state. Persisting it would make a local reading choice durable across unrelated sessions and add migration/config surface for a transient UI affordance.
- **Broadcast the updated log fragment to all subscribers.** Rejected because the state is explicitly per-client. One operator disabling wrapping for long lines must not change another operator's live view.

Consequences:

- Fragment actions can now be used for per-client view state in Mist-backed panels, provided the component opts into state-aware rendering.
- The target app log stream remains the source of log text; the wrap action only re-renders the fragment shell and relies on Mist stream restoration to preserve visible text.
- Durable preference persistence remains a separate future design. If it becomes necessary, it should introduce stable client identity or an explicit user/session preference store rather than overloading Mist's WebSocket client ID.
