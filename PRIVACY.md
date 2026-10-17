# Privacy Policy

_Last updated: 2026-10-16_

**Short version: Kurafuto collects nothing. We do not have a server, and we never see your data.**

## What Kurafuto is

Kurafuto is an app for controlling your own, self-hosted game server panel (Crafty Controller 4) from your iPhone. It is an unofficial app and is not affiliated with Arcadia Technology, Mojang or Microsoft.

## What we collect

Nothing. Kurafuto contains no analytics, no crash reporting, no advertising, no tracking and no third-party SDKs. The developer does not operate any server that the app talks to.

## Where your data goes

Kurafuto connects **only** to the panel address you enter. Everything you do in the app – signing in, starting servers, reading logs, editing files, uploading files you pick – is sent directly from your device to your panel and nowhere else.

## What is stored on your device

| Data | Where | Why |
|---|---|---|
| Access token for your panel | iOS Keychain, this device only | So you stay signed in |
| Panel name, address, username, certificate fingerprint | App storage, encrypted by iOS | So you can switch between panels |
| App settings (e.g. Face ID lock, refresh interval) | App storage | Your preferences |
| For widgets: panel name, server names, status, versions, player counts and the names of up to eight players online, CPU and RAM of the last hour, time of the newest backup, time of the values, your color theme | Storage shared only between the app and its widgets, readable after the first unlock | So the widgets can show your servers without contacting the panel |

Face ID, Touch ID and your passcode are checked by iOS; Kurafuto only learns whether the check succeeded and never sees biometric data.

Your password is never stored; it is only used once to obtain a token from your panel. Server data, logs and files are shown while you look at them and are not saved by Kurafuto, except the short widget summary above. Widgets never contact your panel, and they never show the panel address or your username. Player names appear only on Home Screen widgets and are hidden while your iPhone is locked; Lock Screen widgets show only numbers. If the Face ID lock is on, iOS hides all widget content while your iPhone is locked.

You can remove everything by signing out of a panel in Settings or by deleting the app. Signing out or switching panels also clears the widget summary.

## Live Activities

If you start a server or a backup in Kurafuto, a Live Activity on the Lock Screen and in the Dynamic Island shows its progress: the server's name, how long it has been starting or how far the backup is, and whether it worked. Kurafuto updates it from your iPhone; it uses no push service, so nothing is sent to Apple or anyone else for it. iOS keeps the activity until it ends and may also show it in StandBy and on a paired Apple Watch. If the Face ID lock is on, the activity leaves out the server's name. You can turn Live Activities off in the iPhone's Settings under Kurafuto.

## Siri and Shortcuts

If you use Kurafuto with Siri or Shortcuts, the actions run inside the app on your iPhone and talk only to your panel. To recognize your servers by name, iOS learns their names from Kurafuto; Siri requests are handled by Apple under its own privacy terms. Your panel token never leaves the app.

## Your panel

Your panel is operated by you (or whoever runs it). What the panel logs or stores – for example sign-in attempts or IP addresses – is governed by that panel and its operator, not by Kurafuto.

## This website

getkurafuto.app is a static website hosted on GitHub Pages. It sets no cookies and uses no analytics, fonts, scripts or embeds from third parties. Like any web host, GitHub processes your IP address to deliver the pages and may keep it in short-lived server logs; see the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

If you email support@getkurafuto.app, your message and email address are used only to answer you and are deleted when they are no longer needed.

## Children

Kurafuto is not directed at children. The app collects no data from anyone.

## Changes

Changes to this policy are published at https://getkurafuto.app/privacy/ and in the public repository (`PRIVACY.md`), where the full history is visible.

## Contact

Questions about privacy: support@getkurafuto.app or an issue at https://github.com/miqunosoft/kurafuto/issues. For security issues, see [SECURITY.md](SECURITY.md).
