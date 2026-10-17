# Kurafuto Roadmap

Kurafuto's goal: **everything the Crafty Controller web dashboard can do, as a private, native iPhone app.**

## How this roadmap works

- Milestones are delivered in order. Each one leaves a working app.
- Every checklist item is one pull request (or a small, named series). The first unchecked item of the current milestone is the next task.
- An item is ticked only when its code, tests and docs are merged and its acceptance criteria hold.
- Privacy rule for every milestone: no data collection, no network peer other than the user's panel.

---

## 0.1 – Foundation

**Goal:** a clean, documented repository and a complete UI running on mock data.

- [x] SwiftUI app skeleton with `CraftyService` protocol, `MockCraftyService` and `LiveCraftyService` (ADR 0001, 0003).
- [x] All panel areas as screens with previews.
- [x] Visual design "Instrument" on every screen: dark, gray and light modes, per-metric accent colors, gauges and build-up animations that respect Reduce Motion.
- [x] Privacy baseline: no third parties, Keychain tokens, Application Support storage, privacy manifest, app-switcher cover (ADR 0002).
- [x] Self-signed certificate trust via fingerprint pinning (ADR 0004).
- [x] Governance: `AGENTS.md` (root and folder-local), `CLAUDE.md` pointers, `CONTRIBUTING.md`, `SECURITY.md`, `PRIVACY.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `CODEOWNERS`, issue and PR templates, gitignored `scratch/`.
- [x] CI: `build-and-test` and `DCO` with read-only permissions and SHA-pinned actions.
- [x] First green build in Xcode and CI; fix compiler errors from the uncompiled scaffold.
- [x] Static, tracking-free website with privacy policy for getkurafuto.app (ADR 0006).
- [x] Repository settings applied: ruleset for `main`, secret scanning with push protection, private vulnerability reporting, Pages with custom domain (see `.github/AGENTS.md`).

**Acceptance criteria:** `xcodebuild test` passes locally and in CI; the demo mode works end to end.

## 0.2 – Live MVP

**Goal:** daily use against a real panel for the core loop.

- [x] Verify sign-in, server list, stats, actions, stdin and logs against Crafty 4.7+; record the minimum supported version (4.7.0; see `docs/api/crafty-api-v2.md`).
- [x] Hide UI that the signed-in user has no permission for (`/api/v2/users/{id}/permissions`).
- [x] Live console over the panel WebSocket (port from `websocket_handler.py`), polling as fallback.
- [x] Face ID lock (app launch and before destructive actions).
- [x] Error states for offline panel, expired token and permission denied.

**Acceptance criteria:** start/stop/restart and console work on a real panel; no token or console text appears in logs.

## 0.3 – Management

- [x] Verify and enable schedules (list), backups, files and `server.properties` editing (⚠️ endpoints). Crafty's API cannot list schedules or, on 4.7, backup archives; the app links to the web panel for those (`docs/api/crafty-api-v2.md`).
- [x] File upload for plugins/mods with size limits and path validation.
- [x] Webhook editing and server configuration against a real panel.

## 0.4 – Admin and native extras

- [x] Users and roles against a real panel; verify the permission bit order.
- [x] Localization with String Catalogs (English source; German, Japanese and Simplified Chinese).
- [x] Home Screen and Lock Screen widgets (status and players), reading only cached, non-secret data (ADR 0009).
- [x] App Intents / Shortcuts: start, stop, player count (ADR 0010).

## 1.0 – App Store

- [x] Live Activities for start-up and backups (ADR 0011; updated by the app, no push relay).
- [x] Accessibility pass (VoiceOver, Dynamic Type, contrast).
- [ ] App Store listing, review notes with demo mode, privacy label "Data Not Collected" (`docs/app-store/`).
- [ ] Optional: ask Arcadia Technology about mentioning Crafty in the listing.

## Later (not scheduled)

- Push notifications for crashes. Requires a relay service and therefore an ADR on data flow; must stay opt-in and self-hostable.
- Apple Watch complication.
- iPad layout.
