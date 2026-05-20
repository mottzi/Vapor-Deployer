# Panel visual polish: session-scoped sign-out, tighter live row, boxier pills

The deployer panel got a round of small but meaningful refinements aimed at making the layout read more accurately — session controls separated from deployer controls, the currently-serving deployment row visually emphasised, and the badge shapes brought in line with the buttons around them.

**What changed:**

- **Sign out moved out of the deployer header.** Sign out is a session-scoped action, not a deployer-scoped one, so it no longer lives inside the deployer panel alongside Update. It now sits above the deployer panel, right-aligned to the panel's trailing edge.
- **The live deployment row is now tinted.** The row of the deployment currently serving traffic uses the same background tone as the runtime header bar, making it easier to spot at a glance which build is actually live versus which builds are merely "Built" and available.
- **Status pills are boxier.** The Ready / Running header pills and the per-row status pills (Running, Built, Failed, Stale, …) dropped their fully-rounded pill shape in favour of the same corner radius as the buttons (Update, Sign out, Stop, Restart), so the header reads as a single visual family.
- **Restart button is green, not blue.** The Restart button's hover and active states now use the running (green) color tokens instead of the building (blue) tokens — restart returns the service to its running state, so the color cue matches the outcome.
- **Legacy CSS class names cleaned up.** Internal `dp-supervisor-badge` / `dp-supervisor-btn` class names — left over from when the panel was tied to a specific service manager — were renamed to the more accurate `dp-state-badge` / `dp-control-btn`. No user-visible effect; relevant if you have local overrides targeting those classes.
