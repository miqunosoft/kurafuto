# KurafutoWidgets/ (widget extension)

Home Screen and Lock Screen widgets, and the views of the app's Live Activities. Widgets only read the snapshot the app writes into the App Group container (`WidgetSnapshot`, ADR 0009); they never contact a panel and have no token.

## Map

| File | Owns |
|---|---|
| `KurafutoWidgets.swift` | Widget bundle: `ServerWidget`, `LoadWidget`, `PlayersWidget`, `BackupWidget` (one server, chosen with `SelectServerIntent`), `PanelWidget` and `ServerActivityWidget`; `SnapshotProvider`, `ServerEntity` |
| `WidgetViews.swift` | The widget views after the maintainer's mocks (each view names its mock number) and their previews |
| `ServerActivityWidget.swift` | Lock Screen banner and Dynamic Island of a start-up or backup Live Activity (ADR 0011); the app starts and updates it |

Shared with the app through `project.yml`: `Core/Storage/WidgetSnapshot.swift` (snapshot, store, `ServerLink`), `Core/Models/ServerStats.swift` (`ServerStatus`), `Core/Models/ServerActivity.swift` (`ServerActivityAttributes`), `DesignSystem/Palette.swift` (colors and fonts without app state) and `Resources/Localizable.xcstrings`.

## Rules

- Read only `WidgetSnapshotStore`. No networking, no Keychain, no `UserDefaults`; a new data field goes into `WidgetSnapshot` and needs the ADR's data list, `PRIVACY.md` and the threat model updated.
- Never show panel addresses or usernames. Player names only on Home Screen widgets and always `.privacySensitive()`; Lock Screen widgets show counts.
- The "KURAFUTO クラフト" mark only on large widgets; smaller ones lead with the server or panel name.
- Respect `isPrivate` with `.privacySensitive`, so content stays hidden on a locked device when the app lock is on.
- Home Screen colors come from `Palette` with the snapshot's mode and accent; Lock Screen widgets use system styles and `.widgetAccentable()`.
- The app reloads timelines when the snapshot changes; timelines have one entry and `.never` as policy.
- Live Activities show only what `ServerActivityAttributes` carries; a new field needs ADR 0011, `PRIVACY.md` and the threat model updated. Without a server name (app lock on) they say "Server".
