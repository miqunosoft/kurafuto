import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for a server's start-up or backup. The app starts and updates it (ADR 0011).
struct ServerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ServerActivityAttributes.self) { context in
            ActivityBanner(context: context)
                .activityBackgroundTint(Palette.background(context.attributes.mode))
                .activitySystemActionForegroundColor(Palette.primaryText(context.attributes.mode))
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            // The Dynamic Island is always black, so it uses the dark look.
            let accent = context.attributes.accent.color(for: .dark)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityGlyph(context: context, mode: .dark).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityMeasure(context: context, mode: .dark).font(.mono(.title3, weight: .semibold)).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.displayName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetails(context: context, mode: .dark)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(accent).accessibilityHidden(true)
            } compactTrailing: {
                ActivityMeasure(context: context, mode: .dark).font(.mono(.caption, weight: .semibold))
            } minimal: {
                ActivityMinimal(context: context)
            }
            .widgetURL(context.attributes.link)
            .keylineTint(accent)
        }
    }
}

private struct ActivityBanner: View {
    let context: ActivityViewContext<ServerActivityAttributes>
    private var mode: ThemeMode { context.attributes.mode }

    var body: some View {
        HStack(spacing: 12) {
            ActivityGlyph(context: context, mode: mode)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.displayName).font(.headline).lineLimit(1)
                ActivityDetails(context: context, mode: mode)
            }
            Spacer(minLength: 8)
            ActivityMeasure(context: context, mode: mode).font(.mono(.title2, weight: .semibold))
        }
        .foregroundStyle(Palette.primaryText(mode))
        .padding(16)
    }
}

/// Status line, the backup's progress bar and, once the app stopped updating, a hint to open it.
private struct ActivityDetails: View {
    let context: ActivityViewContext<ServerActivityAttributes>
    let mode: ThemeMode

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 4) {
            Text(context.attributes.status(state))
                .font(.subheadline)
                .foregroundStyle(state.phase == .failed ? Palette.danger(mode) : Palette.secondaryText(mode))
            if context.attributes.kind == .backup, state.phase == .running {
                ProgressView(value: state.progress ?? 0)
                    .tint(context.attributes.accent.color(for: mode))
                    .accessibilityHidden(true)
            }
            if context.isStale, state.phase == .running {
                Text("Open Kurafuto to update").font(.caption).foregroundStyle(Palette.secondaryText(mode))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityGlyph: View {
    let context: ActivityViewContext<ServerActivityAttributes>
    let mode: ThemeMode

    var body: some View {
        let accent = context.attributes.accent.color(for: mode)
        Image(systemName: context.attributes.symbol)
            .font(.title3)
            .foregroundStyle(accent)
            .frame(width: 44, height: 44)
            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Elapsed time while starting, percent while backing up, a check mark or cross at the end.
private struct ActivityMeasure: View {
    let context: ActivityViewContext<ServerActivityAttributes>
    let mode: ThemeMode

    var body: some View {
        switch context.state.phase {
        case .running:
            if context.attributes.kind == .startUp {
                // Counts up from the start without updates from the app; iOS may show it coarser on a dimmed screen.
                Text(timerInterval: context.attributes.started...Date.distantFuture, countsDown: false)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).multilineTextAlignment(.trailing)
                    .frame(maxWidth: 72, alignment: .trailing)
            } else {
                Text(context.state.progress ?? 0, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AccentPreset.green.color(for: mode))
                .accessibilityLabel(context.attributes.status(context.state))
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Palette.danger(mode))
                .accessibilityLabel(context.attributes.status(context.state))
        }
    }
}

private struct ActivityMinimal: View {
    let context: ActivityViewContext<ServerActivityAttributes>

    var body: some View {
        let accent = context.attributes.accent.color(for: .dark)
        if context.attributes.kind == .backup, context.state.phase == .running {
            ProgressView(value: context.state.progress ?? 0) {
                Image(systemName: context.attributes.symbol).font(.caption2)
            }
            .progressViewStyle(.circular)
            .tint(accent)
        } else {
            ActivityMeasure(context: context, mode: .dark).foregroundStyle(accent)
        }
    }
}

#Preview("Backup", as: .content, using: ServerActivityAttributes.preview(.backup)) {
    ServerActivityWidget()
} contentStates: {
    ServerActivityAttributes.ContentState(phase: .running, progress: 0.42)
    ServerActivityAttributes.ContentState(phase: .succeeded, progress: 1)
    ServerActivityAttributes.ContentState(phase: .failed)
}

#Preview("Start-up", as: .dynamicIsland(.expanded), using: ServerActivityAttributes.preview(.startUp)) {
    ServerActivityWidget()
} contentStates: {
    ServerActivityAttributes.ContentState(phase: .running)
    ServerActivityAttributes.ContentState(phase: .succeeded)
}

private extension ServerActivityAttributes {
    static func preview(_ kind: Kind) -> ServerActivityAttributes {
        ServerActivityAttributes(kind: kind, serverID: "a1b2c3", serverName: "Survival SMP", started: .now.addingTimeInterval(-42),
                                 mode: .dark, accent: .cyan)
    }
}
