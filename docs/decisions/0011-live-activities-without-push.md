# 0011. Live Activities are updated by the app, without push

- Status: Accepted
- Date: 2026-10-16

## Context

The roadmap asks for Live Activities for a server's start-up and for backups. A Live Activity lives on the Lock Screen and in the Dynamic Island for minutes to hours, while iOS suspends the app about half a minute after the user leaves it. Activities that keep updating while the app is suspended need ActivityKit push updates through Apple's push service (APNs), which needs a server that holds an APNs key and talks to the user's panel. Kurafuto has no server, and the panel is its only network peer (ADR 0002).

The panel reports a start-up in `GET /stats`: `running` turns true within a second of the start, and `int_ping_results` turns `"True"` once the server answers the panel's ping, which is when players can join (saved every 30 s; Crafty 4.7.0 and 4.11.0). It reports a backup only over its WebSocket: `backup_status` events with a percentage for every archived file, and one at 100 % when the backup ends, also when it failed. The result is then stored in the backup config's `status` (`{"status": "Failed", "message": …}` or `"Standby"`), which only `GET …/backups/backup/{id}` returns. The server row's `backing_up` flag is never set by the panel.

## Decision

- Only the app starts, updates and ends the activities, locally with ActivityKit. No push token is requested (`pushType: nil`), so nothing goes through APNs and there is no new network peer.
- An activity starts only when the user starts a server or a backup in the app and the panel accepted it: the Start buttons, accepting the EULA, Back Up Now and a backup configuration's backup. Siri, Shortcuts and schedules start none.
- Start-up: the app polls `/stats` every 2 seconds. "Ready for players" when the server runs and answers pings; "Did not start" when it stops again or neither runs nor waits to start after 90 seconds. A server that never answers pings (some server types cannot be pinged) is no longer followed after 10 minutes, and its activity disappears.
- Backups: the app listens on the panel WebSocket it already uses for the console. The activity appears with the panel's first progress event, so a panel whose socket is unreachable shows none. At 100 % the app waits two seconds and reads the config's `status` for "Backup finished" or "Backup failed". When the result cannot be read, the activity disappears instead of guessing.
- While the app runs, it refreshes each activity at least every 20 seconds and gives it a stale date one minute ahead. After leaving the app, it keeps updating for the background time iOS grants (about 30 seconds). Then the activity turns stale and says "Open Kurafuto to update". When the app is opened again, start-ups continue; a backup reconnects to the WebSocket up to twice and gives up after 30 seconds without an event, because a backup that ended meanwhile stays silent.
- Ended activities stay on the Lock Screen for 15 minutes. Signing out, switching panels and the next launch end all activities right away.
- The activity holds the server's id, the server's name, the start time, the app's theme and accent color, the phase and the backup's progress. It never holds the panel address, the username, tokens, console output or file names. With the app lock on, the server's name is left out and the activity says "Server", because the Lock Screen is visible without unlocking.
- Tapping an activity opens `kurafuto://server/<id>/console` (start-up) or `/details` (backup), the links widgets already use (ADR 0009).

## Alternatives considered

- **ActivityKit push updates** – rejected: needs a relay server with an APNs key and access to the panel, which contradicts ADR 0002. It may come with the opt-in, self-hostable relay listed under "Later" in the roadmap.
- **Background modes or silent audio to stay awake** – rejected: against the App Store guidelines and the battery.
- **Polling backup state over REST** – not possible: the panel exposes no running backup over REST.
- **Showing the server name with the app lock on** – rejected: it would reveal the servers on a locked phone, unlike the widgets, which hide their content then.

## Consequences

- Activities are accurate while Kurafuto runs and for about half a minute after; after that they may be out of date and say so. Long backups started before leaving the app usually end with the activity stale until the app is opened.
- iOS stores the activity content and shows it on the Lock Screen, in the Dynamic Island, in StandBy and on a paired Apple Watch. It does not leave the user's devices.
- iOS asks the user once whether Kurafuto may show Live Activities; the system setting turns them off.
