# Changelog

All notable user-facing changes to Kurafuto are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Demo mode with sample servers, live console, backups, schedules, users and roles – no panel required.
- Sign in to a Crafty Controller 4 panel with a password (plus 2FA) or an API token. Self-signed panels can be trusted after checking the certificate fingerprint.
- Dashboard with status, players, CPU and RAM for every server; start, stop, restart, kill, back up, clone and update servers.
- Server detail with live CPU/RAM chart, console with quick commands and history, logs, players, schedules, backups, files, server.properties editor, webhooks and configuration.
- Create Java and Bedrock servers.
- Minecraft EULA: when a Java server can't start because its EULA isn't accepted, Kurafuto asks and starts it after you accept. You can also accept the EULA right away when creating a Java server.
- Users and roles with a per-server permission matrix.
- Host metrics and panel announcements.
- Multiple panels, Face ID setting, and a privacy cover in the app switcher.
- App icon: a pixel-art server rack.
- Creating and cloning servers and the Admin tab are hidden when your panel account lacks the rights for them.
- Settings link to the website and privacy policy at getkurafuto.app.
- New "Instrument" design on every screen: dark, gray and light modes, and your own accent color for the app, CPU, RAM, players and storage (Settings → Appearance).
- Animated gauges, live charts and build-up animations; with Reduce Motion they become simple fades.
- The console shows new lines instantly over the panel's WebSocket and falls back to polling when the connection is unavailable. It keeps the last 1,000 lines.
- App lock: with "Lock with Face ID" on, Kurafuto asks for Face ID (or Touch ID or the device passcode) when it opens or returns from the background, and before stopping, killing, deleting or restoring. Turning the lock on or off also needs Face ID.
- Deleting schedules, webhooks, files and folders now asks for confirmation first (and Face ID when the app lock is on).
- Demo mode: start times and console timestamps follow the current clock instead of fixed dates, and starting or stopping a demo server updates its start time.
- Clearer errors: screens tell apart an unreachable panel, a signed-out session and missing rights. When live values stop updating, the dashboard and server screen say so. Failed start, stop, restart and kill actions show why.
- When the panel signs you out (expired token or "Sign Out All Sessions"), Kurafuto asks you to sign in again to the same panel instead of failing quietly.
- Failed saves and actions everywhere (schedules, webhooks, files, backups, players, console commands, users and roles, server settings, announcements) now show why instead of failing silently. The file editors only allow saving once the file has loaded, so a failed load can no longer empty a file.
- Schedules work on real panels: new schedules (every few minutes, hours or days at a set time, cron, or after another schedule) are saved the way the panel's own task runner expects. Before, the panel rejected them. Crafty's API cannot list schedules, so on a real panel the Schedules screen adds new ones and links to the web panel to view, edit or delete them.
- Backups work on real panels: create, edit and delete backup configurations, back up now with the chosen configuration, and restore an archive over the current files or into an emptied server folder (both ask first). "Back Up Now" now also works on Crafty 4.7, where it used to fail inside the panel. Crafty 4.7 cannot list archives over the API, so the Backups screen links to the web panel there. Schedules can now run backups too.
- Files and server.properties work on real panels: browse server folders, open and save text files up to 1 MB, create folders and delete files and folders. If someone changed a file on the panel after you opened it, Kurafuto asks before overwriting it. The server.properties editor now keeps the file's comments and order and has a search field.
- Upload files into any server folder, for example plugins, mods or datapacks, up to 500 MB, with progress and a cancel button. Kurafuto asks before replacing a file with the same name.
- New Servers tab: your panel at the top with a switcher for several panels, crashed servers as a red warning above everything else, one tab per server, and for the selected server its CPU and RAM of the last hour (RAM against the server's memory limit), the players online as pixel faces, Console, Start or Restart and Stop, and the latest console lines. Player faces are drawn on the device; no skins are loaded from the internet.
- Webhooks work on real panels: they load, save, change and delete the way Crafty expects (before, every request failed). Choose Discord, Mattermost, Slack or Teams, the events Crafty really sends (start, stop, crash, backup, JAR update, command, kill), a Jinja2 message with the available variables, and the Discord embed color. Webhook addresses may use http:// or https://. Swipe right on a webhook to have the panel send a test message.
- Server configuration works on real panels: saving sends only what you changed, which the panel now accepts. New settings: shutdown timeout, ignored crash exit codes, counting players in the panel total and the public status page. Start command, IP, port and the status page are read-only for non-superusers, as on the panel.
- Deleting a server now offers both "Remove from Panel" (keeps the folder) and "Delete Server and Files". Before, the app said it deleted the files but the panel kept them.
- Users and roles work on real panels: the user list loads (it used to fail), new users get their password, editing sends only what changed and can set a new password, and roles keep their server rights. Users and roles can now be deleted (after a confirmation). Kurafuto no longer offers what the panel refuses for your own account, such as disabling yourself. Non-superusers with role rights can rename roles; which servers a role covers stays as it is, because only superusers can see it.
- Kurafuto speaks German, Japanese and Simplified Chinese, following the iPhone's language (or the per-app language in Settings). Counts read naturally in every language ("Every day", "1 player"), and numbers and dates follow your region.
- Widgets for the Home Screen and Lock Screen: a server with its players, CPU and RAM (small, medium, and large with Console and Details shortcuts), the CPU of the last hour, who is online, the latest backup, and your whole panel with crashed servers first (medium, large, round and as a line above the clock). They show the values from the app's last refresh with their time and never contact your panel. Player names appear only on the Home Screen, never on the Lock Screen; with the Face ID lock on, widgets stay hidden while the iPhone is locked. Tapping a widget opens that server.
- Siri and Shortcuts: start a server, stop it (after a confirmation; with the app lock on, Kurafuto opens and asks for Face ID) and ask how many players are online, also in German, Japanese and Chinese ("Start Survival SMP in Kurafuto"). The actions need an unlocked iPhone and use your active panel.
- Settings now show the app's real version number.
- Servers tab: the "No data yet" note on an empty CPU or RAM chart is now centered in the chart itself instead of running into the axis labels.
- Security: panels are added and reached over HTTPS only. Before, an `http://` address was accepted and your password or token could have been sent unencrypted; the welcome screen now explains why such an address can't be used.
- Works with Crafty Controller 4.7 and later; sign-in, servers, live values, start/stop/restart, console, logs, schedules, backups, files, webhooks, server configuration, users and roles are verified against real panels.
