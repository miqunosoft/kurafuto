# Architecture decision records

An ADR records one significant decision: its context, the decision, the alternatives and the consequences. ADRs are numbered and never renumbered. To change a decision, write a new ADR that supersedes the old one and update the old one's status.

Write an ADR when a change adds a dependency, changes a trust boundary, adds a network peer, introduces a new kind of stored data, or picks between architectural alternatives.

| # | Title | Status |
|---|---|---|
| [0001](0001-native-swiftui-and-xcodegen.md) | Native SwiftUI app generated with XcodeGen, no dependencies | Accepted |
| [0002](0002-no-data-collection.md) | No data collection; the user's panel is the only network peer | Accepted |
| [0003](0003-service-protocol-and-mock-first.md) | `CraftyService` protocol with a full mock | Accepted |
| [0004](0004-self-signed-certificate-pinning.md) | Trust self-signed panels by explicit certificate pinning | Accepted |
| [0005](0005-licence-and-naming.md) | MIT licence and the name "Kurafuto" | Accepted, amended by 0007 |
| [0006](0006-website-and-domain.md) | Website on getkurafuto.app via GitHub Pages | Accepted |
| [0007](0007-name-and-icon-outside-mit.md) | Name and app icon are not covered by the MIT licence | Accepted, amended by 0008 |
| [0008](0008-no-trademark-registration.md) | No trademark registration | Accepted |
| [0009](0009-widgets-read-a-cached-snapshot.md) | Widgets read a cached snapshot from an App Group | Accepted |
| [0010](0010-siri-and-shortcuts-actions.md) | Siri and Shortcuts actions run inside the app | Accepted |
| [0011](0011-live-activities-without-push.md) | Live Activities are updated by the app, without push | Accepted |

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context

## Decision

## Alternatives considered

## Consequences
```
