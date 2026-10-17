# Threat model

- Last reviewed: 2026-10-17 (HTTPS-only panel addresses)
- Update this document in the same pull request whenever a trust boundary, data category, network peer or stored secret changes.

## System today

An iOS app with no backend. The user adds one or more Crafty Controller panels (URL + password/2FA or API token). The app exchanges the credentials for a bearer token, stores the token in the Keychain, and then calls the panel's HTTP API v2 over HTTPS. Panels are usually on the home network or behind a reverse proxy/tunnel, often with a self-signed certificate. No other host is contacted.

## Assets

| Asset | Why it matters |
|---|---|
| Panel tokens / API keys | Full control over the user's servers, often superuser |
| Passwords and 2FA codes (transient) | Account takeover on the panel |
| Panel addresses, usernames, pinned fingerprints | Reveal the user's infrastructure |
| Server data shown in the app (console, logs, files, player names, IPs in logs) | Personal data of the user and their players |
| Integrity of destructive actions (stop, kill, delete, restore) | Data loss on the user's servers |
| Repository, CI and release pipeline | Supply-chain integrity of the shipped app |

## Actors

- **Network attacker** on the same Wi-Fi or path – intercepts or modifies traffic.
- **Malicious panel content** – a player or plugin controls MOTDs, chat lines, file names and file contents shown in the app.
- **Malicious or compromised panel** – returns hostile responses.
- **Someone with brief access to the unlocked phone** or a shoulder-surfer / screenshot of the app switcher.
- **Malicious contributor or compromised CI action** – tries to add tracking, weaken TLS or exfiltrate secrets.

## Trust boundaries

| # | Boundary | Status |
|---|---|---|
| B1 | App ⇄ panel over the network | Active |
| B2 | Panel responses ⇄ app UI (untrusted content) | Active |
| B3 | App ⇄ device storage (Keychain, Application Support, UserDefaults) | Active |
| B4 | App UI ⇄ other people near or using the device | Active |
| B5 | Repository ⇄ CI ⇄ release | Active |
| B6 | Visitors ⇄ website getkurafuto.app (GitHub Pages) | Active |
| B7 | App ⇄ widget extension (App Group container) and links into the app (`kurafuto://`) | Active |
| B8 | Siri, Shortcuts and automations ⇄ app actions (App Intents) | Active |

## Threats and mitigations

| Threat | Boundary | Mitigation | Status |
|---|---|---|---|
| Token or password interception | B1 | HTTPS only, enforced when a panel is added (`Instance.panelURL`) and again in `APIClient` before anything is sent, the console WebSocket always `wss`; App Transport Security stays on; no `NSAllowsArbitraryLoads`/`NSAllowsLocalNetworking`; ephemeral `URLSession` (no cookie/cache persistence) | Implemented |
| MITM with a forged certificate on a self-signed panel | B1 | Self-signed certificates are rejected unless their SHA-256 fingerprint was explicitly confirmed by the user and pinned per panel (ADR 0004) | Implemented; UI to review/reset pins in 0.2 |
| Token leak through the console WebSocket | B1 | Same host and pinned, ephemeral session as the API; token only in the `Cookie` header, never in the URL; always `wss` | Implemented |
| XSS/markup injection via MOTD, chat, logs, file contents | B2 | All panel strings rendered as plain `Text`; WebSocket console lines are stripped of tags and unescaped into plain text (`CraftyConsoleFeed`), unknown events ignored, console capped at 1,000 lines; Minecraft formatting codes stripped; no `WKWebView`, no HTML/Markdown rendering | Implemented |
| Path traversal via file names from the panel | B2 | Paths come only from panel listings, and listing entries are kept only when they are a single name directly inside the listed folder; new folder names must be a single name without `/`, `\`, `.`/`..` or control characters (`ServerPath.isValidName`) and are checked again in the service; `files/copy`/`move` (traversal in 4.7.0) are not used. Uploads go only into a folder from the listing, under a single ASCII name, at most 500 MB, after confirmation when they would replace a file. Backup archives: only names of the panel's own `yyyy-MM-dd_HH-mm-ss.zip` shape are accepted and only the name is sent back; backup config ids must match the panel's `[a-z0-9-]+` route pattern before they go into a URL | Implemented |
| Hostile or malformed JSON | B2 | `Codable` with lenient, bounded decoding; decoding errors surface as errors, no crashes; no force unwraps outside tests | Implemented |
| Webhook address leaks or misuse | B2, B4 | Webhook URLs usually embed a secret token. The panel, not the app, connects to them, so plain `http://` targets add no network peer to the app; the list shows only the host, the full address only in the editor; addresses are never logged. Scheme, host and port are validated like Crafty 4.11 before saving | Implemented |
| Passwords set for other panel users | B1, B4 | Typed into a secure field, sent once in the request body to the user's own panel over the pinned session, never stored or logged; an empty field keeps the current password. Deleting users and roles needs confirmation | Implemented |
| Token theft from device storage or backups | B3 | Keychain, `AfterFirstUnlockThisDeviceOnly` (excluded from backups and other devices); passwords never stored | Implemented |
| Panel list readable via Files app | B3 | Stored in Application Support with complete file protection, not Documents | Implemented |
| Secrets in logs | B3 | No logging of tokens, passwords, URLs or console output | Rule in `AGENTS.md` |
| App-switcher snapshot leaks panel data | B4 | Privacy cover whenever the scene is not active | Implemented |
| Widgets expose panel data or credentials | B3, B4, B7 | The extension has no token and no network access to the panel; it reads only `WidgetSnapshot` (panel name, server names, status, versions, player counts, up to eight player names, CPU/RAM of the last hour, newest backup time, theme), never addresses, usernames, console output or files. Player names are shown only on Home Screen widgets and are always privacy-sensitive; Lock Screen widgets show counts. The file lives in the App Group container with `completeUntilFirstUserAuthentication` protection and is deleted on sign-out and panel switch. With the app lock on, all widget content is privacy-sensitive and hidden on a locked device (ADR 0009) | Implemented |
| Server stopped by voice, automation or someone holding the unlocked phone | B4, B8 | App Intents need an unlocked device; Stop asks for confirmation and, with the app lock on, brings the app to the front for its lock screen and a fresh Face ID or passcode check, and fails rather than skipping it (iOS refuses Face ID in the background). Only start, stop and player count exist; no kill, delete or restore (ADR 0010) | Implemented |
| Token exposure through Siri or Shortcuts | B8 | Intents run in the app process with its own client; iOS receives only server ids, names and dialog text, never the token or panel address | Implemented |
| Hostile `kurafuto://` link from another app or website | B7 | Only `kurafuto://server/<id>` with a letters/digits/`-` id, optionally followed by `/console` or `/details`, is accepted; the app opens that server only if the active panel lists it and never runs an action from a link (opening the console sends nothing) | Implemented |
| Accidental destructive action | B4 | Confirmation dialogs for stop, kill, restore and delete; typed name to delete a server | Implemented |
| Unauthorised use of an unlocked phone | B4 | Optional app lock (`AppLock`, `deviceOwnerAuthentication`: Face ID/Touch ID with passcode fallback) on launch and return from background, with the app hidden behind a lock screen; confirmed stop, kill, delete and restore need a fresh check; turning the lock off needs one too | Implemented |
| Third-party data leak (avatars, analytics, SDKs) | B1, B5 | No third-party hosts or dependencies (ADR 0002); privacy manifest declares none; PR template checklist | Implemented |
| Malicious CI change or compromised action | B5 | Read-only `GITHUB_TOKEN`, SHA-pinned actions, `persist-credentials: false`, CODEOWNERS on `.github/` and `scripts/`, DCO | Implemented |
| Website tracks visitors or loads third-party content | B6 | Static HTML only; CSP `default-src 'none'` with `'self'` styles and images; `no-referrer`; no scripts, cookies, fonts or embeds; HTTPS enforced by the `.app` HSTS preload (ADR 0006) | Implemented |
| Website defacement via the deploy pipeline | B5, B6 | Pages workflow runs only on `main`, SHA-pinned actions, minimal permissions; CODEOWNERS on `site/` | Implemented |
| Secrets committed to the repository | B5 | `.gitignore` for local xcconfig, keys and profiles; secret scanning with push protection (repository setting) | Implemented / setting pending |

## Out of scope

- Vulnerabilities inside Crafty Controller itself (e.g. known stored XSS in the web panel, path traversal in 4.7.0 file endpoints). Kurafuto does not render panel content as HTML and avoids the affected endpoints until verified.
- Jailbroken devices and attackers with the device passcode.
