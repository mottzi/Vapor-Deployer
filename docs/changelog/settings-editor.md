# Environment variables, editable from the panel

The deployer now ships a settings page for editing the target app's environment variables directly from the web panel. Until now, changing a value in the `.env` file meant SSHing into the host and editing the file by hand; the panel can now do it for you, with the same atomic write semantics the deployer uses for its own state.

**What's new:**

- **Settings page on the panel.** A gear button on the panel toolbar opens an editor for the target app's `.env` file. Each variable is a row of two fields — key and value — with buttons to add a new pair, delete a pair, and reveal/hide the value. Values are masked by default so secrets don't sit on screen.
- **Atomic writes.** Saving the form rewrites the whole `.env` file as a single atomic operation: either every change lands or none does. The target app keeps reading the previous file until you explicitly restart it from the panel — there is no half-written intermediate state.
- **Validation with full-form feedback.** Invalid keys (empty, duplicate, or containing forbidden characters) are flagged inline on the offending row, and the submitted values are preserved so you don't lose work while fixing the problem.
- **Restart reminder, not auto-restart.** Saving does not restart the target app. The page tells you to use Restart from the panel when you're ready to pick up the new values — so a sequence of edits doesn't bounce the service repeatedly.
- **The value field is not a password input.** Browsers classify any visually-masked `<input>` as a credential field and offer to autofill saved logins. The value field is built as an editable text region instead, so the panel's own saved login never gets suggested as an env var value.
- **Visible "unsaved changes" cue.** The Save button lights up the moment you edit a key, edit a value, or delete a row that had content, and stays lit until you save. Adding an empty row stays neutral until you type into it.
- **Back-with-unsaved-changes is handled gracefully.** Trying to leave with pending edits opens a confirmation dialog with Discard / Save / Cancel. Picking Save lands you on the page you were trying to reach, not back on settings; picking Discard or Cancel does what it says. The browser's native "Leave page?" dialog is reserved for refresh/close/history navigation — it doesn't fire when you click Save.
