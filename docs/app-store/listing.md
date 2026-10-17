# App Store Listing

Primary language: **English (U.S.)**. The app itself is localized into German, Japanese and Simplified Chinese; listing localizations for those languages can follow.

Everything below is what goes into App Store Connect for 1.0. Claims in the description and review notes must match the shipped build (Guideline 2.3.1); update this file in the same pull request as a feature change.

| Field | Limit | Value |
|---|---|---|
| Name | 30 | **Kurafuto – Server Panel** (23) |
| Subtitle | 30 | **Control your game servers** (25) |
| Bundle ID | – | `dev.miquno.kurafuto` (widgets: `dev.miquno.kurafuto.widgets`, App Group `group.dev.miquno.kurafuto`) |
| Category | – | Utilities (secondary: Developer Tools) |
| Privacy policy URL | – | https://getkurafuto.app/privacy/ |
| Support URL | – | https://getkurafuto.app |
| Marketing URL | – | https://getkurafuto.app |
| Support email | – | support@getkurafuto.app |
| Copyright | – | 2026 miquno |
| Privacy label | – | Data Not Collected (see below) |
| Price | – | Free, no in-app purchases, no ads (→ non-trader under the EU DSA, see `legal-and-naming.md`) |

Alternative names: *Kurafuto – Game Server Admin* (28), *Kurafuto: Server Control* (24).
Alternative subtitles: *Start, console, backups & more* (30), *Your self-hosted server panel* (29).

## Keywords (100 characters, comma-separated, no spaces)

```
server,panel,admin,homelab,selfhosted,console,backup,gameserver,hosting,remote,status,players,world
```

No third-party brands (Crafty, Minecraft, Paper, …) – Guideline 2.3.7.

## Promotional text (170)

> Manage your self-hosted game servers from anywhere: start, stop, live console, backups and schedules – right from your iPhone, with widgets and Live Activities.

## Description

> Kurafuto puts your self-hosted game server panel in your pocket.
>
> Start, stop and restart servers, watch the live console, send commands, manage players and backups, and keep an eye on every server from your Home Screen – wherever you are.
>
> **Compatible with Crafty Controller 4.7 and later.** Kurafuto connects to the panel you run yourself; it does not host servers.
>
> FEATURES
> • Servers at a glance: status, players, and CPU and RAM of the last hour
> • Live console with quick commands and history
> • Players: op, kick, ban, game mode and whitelist
> • Backups: back up now, edit backup settings, restore and delete archives (archive list on Crafty 4.11 and later)
> • New schedules for restarts, backups and commands: intervals, set times, cron or after another task
> • Files: browse folders, edit text files and server.properties, upload plugins, mods and datapacks
> • Webhooks for Discord, Slack, Teams and Mattermost
> • Users and roles with per-server permissions
> • Create, clone and update servers
> • Home Screen and Lock Screen widgets
> • Live Activities while a server starts or a backup runs
> • Siri and Shortcuts: start or stop a server, ask how many players are online
> • Optional Face ID lock, also before stopping or deleting anything
> • Several panels, self-signed certificates after you check the fingerprint
> • English, German, Japanese and Simplified Chinese
>
> PRIVACY
> Kurafuto talks only to the panel you add, over HTTPS. Your token stays in the iPhone's Keychain. No accounts, no tracking, no analytics.
>
> Kurafuto is an unofficial app and is not affiliated with or endorsed by Arcadia Technology, Mojang or Microsoft.

## Review notes

> Kurafuto is a client for Crafty Controller, a free, self-hosted web panel for game servers that people run on their own computers or home servers. The app has no backend and no accounts of its own: users sign in to their own panel with its address and their panel account or an API token.
>
> To review all features without a panel, tap "Try the Demo with Sample Data" on the welcome screen. The demo runs entirely on the device with sample servers, players, console output, backups, files, webhooks, users and roles; every screen and action works there, and nothing is sent anywhere.
>
> Notes:
> • Local network: panels usually run on the user's home network, so iOS asks for local network access when the user connects to such an address. The demo never asks.
> • Self-signed certificates: Crafty uses one by default. Kurafuto shows its SHA-256 fingerprint and trusts it only after the user confirms; App Transport Security stays on, and plain HTTP is refused.
> • Face ID is optional (Settings → Lock with Face ID).
> • Live Activities are updated by the running app only; there is no push service.
> • The app is unofficial; this is stated in the description and in Settings.

If a live test panel is available at submission time, add: *Live test panel: https://… · user `appreview` · password …* – never commit its address or password to this repository.

## App Privacy (App Store Connect questionnaire)

- **Do you or your third-party partners collect data from this app?** No → label "Data Not Collected".
- Why this holds (Apple's definition: data transmitted off the device so that the developer or third parties can access it beyond servicing the request in real time):
  - The only network peer is the panel the user adds and runs (`APIClient`, HTTPS only, redirects only within the panel). The developer runs no server.
  - No analytics, crash reporting, ads or third-party SDKs; no dependencies (ADR 0002).
  - Widget snapshot, Live Activities and preferences stay on the device; Siri/Shortcuts phrases are processed by Apple under its own terms (`PRIVACY.md`).
- **Tracking:** No. `PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no collected data, and UserDefaults with reason `CA92.1` only. The widget extension uses no required-reason API.
- **Export compliance:** HTTPS through Apple's frameworks only → `ITSAppUsesNonExemptEncryption = false` (set in `project.yml`).

## Accessibility (App Store accessibility labels)

Declare only what was checked on the shipped build:

| Feature | Status |
|---|---|
| Dark Interface | Yes – dark and gray modes |
| Larger Text | Yes – checked at the largest accessibility size on every screen in the simulator (accessibility pass) |
| Sufficient Contrast | Yes – all text colors meet WCAG AA in every mode and accent (`AccessibilityTests`) |
| Reduced Motion | Yes – animations follow Reduce Motion |
| Differentiate Without Color Alone | App screens show status as text or a symbol; check the widgets before declaring |
| VoiceOver | Check on a device with VoiceOver on before declaring |
| Voice Control | Check on a device before declaring |
| Captions, Audio Descriptions | Not applicable (no audio or video) |

## Age rating

Suggested answers: no violence, sexual content, profanity, gambling, medical or drug content, no unrestricted web access (links open in Safari), no advertising. The console and the player list show what players write and are named on the user's own server; whether that counts as user-generated content or messaging in the questionnaire is the maintainer's call when filling it in.

## Screenshots

Taken from the demo mode, in English, dark mode, at the sizes App Store Connect asks for (6.9" iPhone). Suggested set: Servers tab, server screen, console, backups, widgets on the Home Screen, Live Activity on the Lock Screen. No real panel addresses, player names or IPs.

## Needs the Apple Developer Program (not done yet)

- Register the bundle IDs and the App Group, and set the team in `BuildConfig.local.xcconfig` (gitignored).
- Create the app record in App Store Connect and fill in the fields above, the privacy questionnaire, the accessibility labels, the age rating and the DSA trader status (non-trader).
- Archive and upload a build; test it in TestFlight on a device: Face ID lock, widgets, Live Activities, Siri, and VoiceOver.
- Take the screenshots, then submit for review.
