# Architecture

Kurafuto is a single-target SwiftUI app with no backend of its own and no third-party dependencies. It talks to exactly one kind of server: the Crafty Controller panel that the user adds.

```
┌──────────────────────── iPhone ────────────────────────┐
│ Features/*  (SwiftUI views, one folder per panel area) │
│        │  uses only                                    │
│        ▼                                               │
│ CraftyService (protocol) ◄── AppState picks one:       │
│   ├─ MockCraftyService   demo, previews, tests         │
│   └─ LiveCraftyService ──► APIClient ──HTTPS──────────┼──► User's Crafty panel
│                                 │  (pinned if          │     (API v2, bearer token)
│ Keychain ◄── KeychainStore      │   self-signed)       │
│ App Support ◄── InstanceStore (panel list, no secrets) │
└────────────────────────────────────────────────────────┘
```

## Layers

1. **Features** – screens. They own view state only, call `app.service`, and show errors via `LoadableView`.
2. **Services** – `CraftyService` is the single seam. `LiveCraftyService` maps calls to API v2 endpoints (see `docs/api/crafty-api-v2.md`); `MockCraftyService` simulates the same behavior in memory.
3. **Networking** – `APIClient` handles the `{status, data}` envelope (and the backup routes that answer without it), bearer tokens, errors, and certificate trust.
4. **Storage** – `KeychainStore` for tokens, `InstanceStore` for the list of panels.

## Data ownership

| Data | Where it lives | Leaves the device? |
|---|---|---|
| Panel token / API key | Keychain, `AfterFirstUnlockThisDeviceOnly` | Only to that panel, in the `Authorization` header |
| Password, 2FA code | Memory during sign-in only | Only to that panel's login endpoint |
| Panel list (name, URL, username, pinned cert hash) | `Application Support/instances.json`, complete file protection | Never (part of the user's own device backup) |
| App preferences (Face ID toggle, refresh interval) | `UserDefaults` | Never |
| Widget snapshot (panel name; server names, status, versions, player counts and names, CPU/RAM of the last hour, newest backup time; time, theme, app-lock flag) | App Group container `widget-snapshot.json`, `completeUntilFirstUserAuthentication` | Never (ADR 0009) |
| Live Activity (server id and name – no name with the app lock on –, start time, theme, start-up or backup phase and progress) | iOS (ActivityKit), until the activity ends | Never; no push token (ADR 0011) |
| Server data, logs, files | Memory while displayed | Never stored by Kurafuto |

Kurafuto has no server, no analytics and no third-party network calls. See `PRIVACY.md` and ADR 0002.

## Live updates

`LiveCraftyService.consoleStream` loads the console backlog from `/logs`, then follows the panel's undocumented WebSocket `/ws` – the same one the web panel uses, on the same host and pinned session, authenticated with the `token` cookie. Parsing lives in `CraftyConsoleFeed`. If the socket is refused, drops or stops answering pings, the stream falls back to polling `/logs` every 2 seconds. Starting a server also opens the socket briefly, because the panel reports a missing Minecraft EULA only there, and a backup's Live Activity listens on it for the panel's progress events. Stats are still polled from `/stats`. Everything stops when the view disappears (`.task` cancellation).

## Errors

`APIClient.failure` maps panel answers to `CraftyError`, and `Error.panelProblem` sorts every error into offline, session expired, permission denied or other. `LoadableView`, `StaleValuesBanner` and `.errorAlert` show the matching message. A rejected token makes the active client post `.panelSessionExpired` (no payload); `RootView` then shows `SignInAgainView`, which replaces the token in the Keychain.

## App lock

`AppState.lock` (`AppLock`) wraps LocalAuthentication's `deviceOwnerAuthentication`, so Face ID or Touch ID falls back to the device passcode. When the lock is on, `RootView` covers the app with `LockView` at launch and after the scene went to the background (not on `.inactive`, which the Face ID prompt itself triggers). Destructive actions go through `.destructiveConfirmation` or `lock.authorize(_:)`. iOS answers only yes or no; no biometric data reaches the app.

## Widgets

`KurafutoWidgets` is a WidgetKit extension with five widgets, laid out after the maintainer's mocks: Server (small, medium, large, Lock Screen rectangular and inline), Server Load (small, Lock Screen rectangular), Players (medium), Backup (small) and Panel (medium, large, Lock Screen circular and inline). Widgets for one server are configured with `SelectServerIntent`. The extension never talks to a panel and has no token. After each successful refresh, the Servers tab hands its servers, stats, history and newest backups to `WidgetSync`, which writes a `WidgetSnapshot` into the shared App Group container (right away for status, player and backup changes, every five minutes for live load) and reloads the timelines. While widgets are placed, the Servers tab loads the last hour of every server once per load, and the newest backup only for a placed backup widget. Signing out and switching panels clear the snapshot. A widget opens `kurafuto://server/<id>[/console|/details]`; `RootView` passes it on, and the Servers tab opens that server only if the panel lists it (ADR 0009). The extension shares `WidgetSnapshot.swift`, `ServerStats.swift`, `Palette.swift` and the String Catalog with the app.

## Live Activities

When the panel accepted a start or a backup from the app, `AppState.followInLiveActivity` hands it to `ServerActivities` (`App/`), which requests a Live Activity with `ServerActivityAttributes` (`Core/Models/ServerActivity.swift`, shared with the extension) and follows it on the main actor. Start-ups poll `/stats` every 2 seconds and read `StartUpWatch`: ready once the server runs and answers the panel's ping (`ServerStats.answersPing`). Backups read `CraftyService.backupProgress`, which in the live service follows the panel WebSocket's `backup_status` events and then the config's `status`; the activity appears with the first event. There is no push token: only the running app updates the activities, so a heartbeat moves their stale date forward every 20 seconds, a background task keeps them updating for about half a minute after leaving the app, and afterwards they show as stale until the app is opened again. Signing out, switching panels and the next launch end them. `ServerActivityWidget` in the extension draws the Lock Screen banner and the Dynamic Island and opens `kurafuto://server/<id>/console` or `/details` (ADR 0011).

## Siri and Shortcuts

`Features/Shortcuts/ServerShortcuts.swift` defines the App Intents Start Server, Stop Server and Player Count, their `PanelServerEntity` (listed live from the active panel) and the App Shortcuts phrases. They run in the app's process: `KurafutoApp` hands its `AppState` to `ServerShortcuts` at launch, also when iOS starts the app in the background for an action, and the intents use the active panel's service. All need an unlocked device; Stop asks for confirmation and goes through `AppLock.authorize`. With the app lock on, Stop first brings the app to the front, because iOS allows Face ID only for foreground apps, and waits for the lock screen to be unlocked (ADR 0010). The Servers tab updates the App Shortcuts parameters after loading, so Siri knows the server names.

## Localization

All UI text is English in code and translated in `Kurafuto/Resources/Localizable.xcstrings` (String Catalog: German, Japanese, Simplified Chinese, with plural variations); the permission prompts are in `InfoPlist.xcstrings` and the Siri phrases in `AppShortcuts.xcstrings`. The compiler records every localizable string (`SWIFT_EMIT_LOC_STRINGS`), and CI's `scripts/check-localizations.sh` fails when the catalog and the code drift apart or a translation is missing. Panel data is never translated or looked up as a key.

## Accessibility

Every control has a VoiceOver label, values are read as one element (gauges, metrics, player counts), and section titles are headers. Text uses Dynamic Type text styles; rows of side-by-side content use `AdaptiveStack`, which becomes a column at the accessibility sizes, and fixed sizes that hold text grow with `@ScaledMetric`. The palette's text colors reach WCAG AA (4.5:1) on every surface and on tints of up to 16 % in all three modes, which `AccessibilityTests` checks for every accent preset. Motion follows Reduce Motion, and status is never shown by color alone.

## Decisions

See `docs/decisions/`.
