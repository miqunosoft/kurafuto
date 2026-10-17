import SwiftUI

/// "Instrument" design: graphite surfaces, monospaced data, one accent color per metric.
/// Own visual identity – deliberately do NOT copy the Crafty or Minecraft logo/color scheme
/// (trademark law, App Review guideline 4.1).
/// Colors read `Appearance.shared`, so any view using them redraws when the user changes the look.
@MainActor
enum Theme {
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 14

    private static var mode: ThemeMode { Appearance.shared.mode }

    // MARK: Surfaces

    static var background: Color { background(for: mode) }
    static var surface: Color { surface(for: mode) }

    /// Per-mode variants, e.g. for the theme previews in Settings.
    static func background(for mode: ThemeMode) -> Color { Palette.background(mode) }
    static func surface(for mode: ThemeMode) -> Color { Palette.surface(mode) }
    static func primaryText(for mode: ThemeMode) -> Color { Palette.primaryText(mode) }

    /// Inset areas inside a card (gauge tiles, icon tiles).
    static var sunken: Color { Palette.sunken(mode) }
    static var stroke: Color { Palette.stroke(mode) }
    static var divider: Color { Palette.divider(mode) }
    /// Ring and meter tracks.
    static var track: Color { Palette.track(mode) }
    static var secondaryText: Color { Palette.secondaryText(mode) }

    /// The console stays dark in every mode, so its line colors always use the dark-mode shades.
    static let console = Color(hex: 0x07090B)
    static let consoleText = Color(hex: 0xC3C9D0)
    static let consoleWarning = AccentPreset.amber.color(for: .dark)
    static let consoleError = Color(hex: 0xFF6B5E)
    static var consoleCommand: Color { Appearance.shared.preset(for: .accent).color(for: .dark) }
    static var consoleChat: Color { Appearance.shared.preset(for: .players).color(for: .dark) }

    // MARK: Accents

    static var accent: Color { Appearance.shared.color(for: .accent) }
    static var cpu: Color { Appearance.shared.color(for: .cpu) }
    static var ram: Color { Appearance.shared.color(for: .ram) }
    static var players: Color { Appearance.shared.color(for: .players) }
    static var storage: Color { Appearance.shared.color(for: .storage) }

    /// Text and icons placed on an accent fill.
    static var onAccent: Color { Palette.onAccent(mode) }

    static var danger: Color { Palette.danger(mode) }
    static var warning: Color { Palette.warning(mode) }

    static func color(for status: ServerStatus) -> Color { Palette.color(for: status, mode: mode, accent: accent) }
}

// MARK: - Surfaces

extension View {
    /// The standard raised card: surface fill, hairline stroke, large radius.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Screen background for scroll views, lists and forms.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }

    /// Row styling for `List`/`Form` content. Apply to a `Group` around the sections.
    func themedRows() -> some View {
        modifier(ThemedRows())
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

private struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            // List cells keep the separator tint they were created with, so a mode switch
            // would leave dark separators on light rows. A new identity rebuilds the cells;
            // screen state is unaffected because it lives outside the list.
            .id(Appearance.shared.mode)
            .background(Theme.background.ignoresSafeArea())
    }
}

private struct ThemedRows: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.divider)
    }
}

/// Small uppercase monospaced label above a group of cards.
struct SectionLabel: View {
    let title: LocalizedStringResource
    init(_ title: LocalizedStringResource) { self.title = title }
    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.mono(.caption2, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row that turns into a column at the accessibility text sizes, so long text gets the full width
/// instead of wrapping letter by letter next to its neighbours.
struct AdaptiveStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// Rounded square holding a symbol, as used in list rows and the panel header.
struct IconTile: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.stroke))
            .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Status dot with a halo; online and starting servers "breathe" unless Reduce Motion is on.
struct StatusDot: View {
    let status: ServerStatus
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var animated: Bool { !reduceMotion && [.online, .starting, .updating].contains(status) }

    var body: some View {
        let color = Theme.color(for: status)
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(pulse ? 0.05 : 0.22))
                    .frame(width: size * (pulse ? 2.8 : 2), height: size * (pulse ? 2.8 : 2))
            }
            .frame(width: size * 2.8, height: size * 2.8)
            .onAppear { startPulse() }
            .onChange(of: status) { pulse = false; startPulse() }
            .accessibilityHidden(true)
    }

    private func startPulse() {
        guard animated else { return }
        let speed = status == .online ? 1.6 : 0.7
        withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) { pulse = true }
    }
}

struct StatusBadge: View {
    let status: ServerStatus
    var body: some View {
        HStack(spacing: 2) {
            StatusDot(status: status, size: 6)
            Text(status.label.uppercased()).font(.mono(.caption2, weight: .semibold))
        }
        .foregroundStyle(Theme.color(for: status))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gauges

/// Circular gauge for a 0…100 value. Fills up when it appears and follows live changes.
struct RingGauge: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var clamped: Double { min(max(value, 0), 100) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(clamped / 100, format: .percent.precision(.fractionLength(0)))
                .font(.mono(.subheadline, weight: .semibold))
                .contentTransition(.numericText(value: clamped))
                .animation(.snappy, value: clamped)
        }
        .padding(lineWidth / 2)
        .onAppear {
            if reduceMotion { shown = clamped; return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(delay)) { shown = clamped }
        }
        .onChange(of: clamped) { _, new in
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85)) { shown = new }
        }
    }
}

/// Inset tile with a ring gauge and a caption, as in the dashboard's featured server.
struct GaugeTile: View {
    let title: LocalizedStringResource
    let value: Double
    let color: Color
    var caption: String?
    var delay: Double = 0
    /// Grows with the percentage inside, so large text still fits the ring.
    @ScaledMetric(relativeTo: .subheadline) private var ringSize: CGFloat = 64

    var body: some View {
        let title = String(localized: title)
        let percent = (min(max(value, 0), 100) / 100).formatted(.percent.precision(.fractionLength(0)))
        VStack(spacing: 8) {
            RingGauge(value: value, color: color, delay: delay)
                .frame(width: ringSize, height: ringSize)
            Text(caption.map { "\(title) \($0)" } ?? title)
                .font(.mono(.caption2))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption.map { "\(percent), \($0)" } ?? percent)
    }
}

/// Inset tile with a single value, the gauge tiles' plain sibling.
struct ValueTile: View {
    let title: LocalizedStringResource
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textCase(.uppercase).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.mono(.title3, weight: .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Thin horizontal meter for a value within a total.
struct MeterBar: View {
    let value: Double
    var total: Double = 100
    let color: Color
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var fraction: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { shown = fraction }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(reduceMotion ? nil : .snappy) { shown = new }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

extension View {
    /// Build-up animation: content rises, sharpens and fades in, staggered by `index`.
    /// Reduce Motion keeps only a short fade.
    func entrance(_ index: Int = 0) -> some View {
        modifier(EntranceModifier(index: index))
    }
}

private struct EntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .scaleEffect(visible || reduceMotion ? 1 : 0.97)
            .blur(radius: visible || reduceMotion ? 0 : 6)
            .onAppear {
                guard !visible else { return }
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.82).delay(Double(min(index, 12)) * 0.06)
                withAnimation(animation) { visible = true }
            }
    }
}

/// Primary and tinted buttons in the Instrument look.
struct InstrumentButtonStyle: ButtonStyle {
    /// `console` is the always-dark console look.
    enum Kind { case filled, tinted, outline, console }
    var kind: Kind = .filled
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        InstrumentButton(configuration: configuration, kind: kind, color: color)
    }

    private struct InstrumentButton: View {
        let configuration: Configuration
        let kind: Kind
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                .overlay {
                    if kind == .outline {
                        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).strokeBorder(Theme.stroke)
                    }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .filled: Theme.onAccent
            case .tinted: color
            case .outline: .primary
            case .console: Theme.consoleText
            }
        }

        private var background: Color {
            switch kind {
            case .filled: color
            case .tinted: color.opacity(0.14)
            case .outline: Theme.sunken
            case .console: Theme.console
            }
        }
    }
}

// MARK: - Loading

/// Uniform loading/error wrapper for every list.
enum Loadable<T> {
    case idle, loading, loaded(T), failed(Error)

    var value: T? { if case .loaded(let v) = self { v } else { nil } }
}

struct LoadableView<T, Content: View>: View {
    @Environment(AppState.self) private var app
    let state: Loadable<T>
    let retry: () async -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
        case .failed(let error):
            let problem = error.panelProblem
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message(for: error))
            } actions: {
                if problem == .sessionExpired {
                    Button("Sign In Again") { app.sessionExpired = true }
                        .buttonStyle(InstrumentButtonStyle()).frame(width: 200)
                }
                Button("Try Again") { Task { await retry() } }
                    .buttonStyle(InstrumentButtonStyle(kind: problem == .sessionExpired ? .outline : .filled))
                    .frame(width: 200)
            }
            .background(Theme.background.ignoresSafeArea())
        case .loaded(let v):
            content(v)
        }
    }
}

extension PanelProblem {
    var title: LocalizedStringKey {
        switch self {
        case .offline: "Panel Unreachable"
        case .sessionExpired: "Signed Out"
        case .permissionDenied: "No Permission"
        case .other: "Error"
        }
    }

    var symbol: String {
        switch self {
        case .offline: "wifi.slash"
        case .sessionExpired: "person.crop.circle.badge.exclamationmark"
        case .permissionDenied: "lock.fill"
        case .other: "exclamationmark.triangle"
        }
    }

    func message(for error: Error) -> String {
        switch self {
        case .offline:
            String(localized: "Check that the panel is running and that your iPhone can reach it, for example on the same network or over VPN.")
        case .sessionExpired:
            String(localized: "Your session on this panel has ended. Sign in again to continue.")
        case .permissionDenied:
            String(localized: "Your panel account is not allowed to do this. Ask the panel's admin for access.") + "\n\n" + error.localizedDescription
        case .other:
            error.localizedDescription
        }
    }
}

/// Live values could not be refreshed; the screen keeps the last ones it got.
struct StaleValuesBanner: View {
    let problem: PanelProblem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: problem.symbol).foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title).font(.subheadline.weight(.semibold))
                Text("Showing the last known values.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

extension Binding where Value == Error? {
    /// Runs `operation`; a failure lands here and shows through `.errorAlert`. Returns whether it succeeded.
    @MainActor @discardableResult
    func capture(_ operation: () async throws -> Void) async -> Bool {
        do { try await operation(); return true }
        catch { wrappedValue = error; return false }
    }
}

extension View {
    /// Shows why an action failed. A rejected token is left to the sign-in sheet in `RootView`.
    func errorAlert(_ error: Binding<Error?>) -> some View {
        let shown = error.wrappedValue.flatMap { $0.panelProblem == .sessionExpired ? nil : $0 }
        return alert(shown?.panelProblem.title ?? "Error",
                     isPresented: Binding(get: { shown != nil }, set: { if !$0 { error.wrappedValue = nil } }),
                     presenting: shown) { _ in
            Button("OK", role: .cancel) {}
        } message: { e in
            Text(e.panelProblem.message(for: e))
        }
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

/// Confirmation helper for dangerous actions (stop, kill, delete).
struct ConfirmAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let buttonLabel: String
    let perform: () async -> Void
}
