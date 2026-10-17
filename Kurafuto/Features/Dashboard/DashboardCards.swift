import Charts
import SwiftUI

// The building blocks of the Servers tab, top to bottom.

/// Panel name (a menu to switch panels when there are several), connection state and the create button.
struct DashboardHeader: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    let problem: PanelProblem?
    let onCreate: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "KURAFUTO  クラフト")
                    .font(.caption.weight(.medium)).tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                panelTitle
                HStack(spacing: 6) {
                    Circle().fill(problem == nil ? Theme.accent : Theme.warning).frame(width: 8, height: 8)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 8)
            if let onCreate {
                Button(action: onCreate) {
                    Image(systemName: "plus").font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create server")
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var panelTitle: some View {
        let name = Text(app.activeInstance?.name ?? String(localized: "Servers"))
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(1).minimumScaleFactor(0.6)
        let others = app.instanceStore.instances.filter { $0.id != app.activeInstance?.id }
        if app.isMock || others.isEmpty {
            name.accessibilityAddTraits(.isHeader)
        } else {
            Menu {
                ForEach(others) { instance in
                    Button(instance.name) { app.switchTo(instance) }
                }
            } label: {
                HStack(spacing: 8) {
                    name
                    Image(systemName: "chevron.down").font(.title3.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityLabel("\(app.activeInstance?.name ?? String(localized: "Panel")), switch panel")
        }
    }

    private var subtitle: String {
        if app.isMock { return String(localized: "Demo · sample data") }
        let host = app.activeInstance?.baseURL.host() ?? ""
        return switch problem {
        case nil: String(localized: "\(host) · Connected")
        case .offline: String(localized: "\(host) · Unreachable")
        case .sessionExpired: String(localized: "\(host) · Signed out")
        case .permissionDenied, .other: String(localized: "\(host) · Values not updating")
        }
    }
}

/// A crashed server, shown above everything else.
struct CrashBanner: View {
    let server: Server

    var body: some View {
        AdaptiveStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill").font(.title2)
                Text("\(server.serverName) crashed").font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 4) {
                Text("Logs").font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .fixedSize()
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.danger.opacity(0.25)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(server.serverName) crashed")
        .accessibilityHint("Opens the server and its logs")
    }
}

/// One tab per server with a sliding underline; crashed servers carry a red dot.
struct ServerTabBar: View {
    let servers: [Server]
    let stats: [String: ServerStats]
    @Binding var selection: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Namespace private var underline

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 26) {
                    ForEach(servers) { server in tab(server) }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: selection) { _, id in
                withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func tab(_ server: Server) -> some View {
        let selected = server.id == selection
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { selection = server.id }
        } label: {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 4) {
                    Text(server.serverName)
                        .font(.headline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                        .lineLimit(1)
                    if stats[server.id]?.crashed == true {
                        if withoutColor {
                            Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(Theme.danger)
                        } else {
                            Circle().fill(Theme.danger).frame(width: 7, height: 7)
                        }
                    }
                }
                ZStack {
                    Capsule().fill(Color.clear).frame(height: 3)
                    if selected {
                        Capsule().fill(Theme.accent).frame(height: 3)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
            }
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(server.id)
        .accessibilityLabel(server.serverName)
        .accessibilityValue(stats[server.id]?.status.label ?? "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Name, version, status and the last hour of CPU and RAM of the selected server.
struct ServerOverviewCard: View {
    let server: Server
    let stats: ServerStats?
    let history: [StatSample]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var status: ServerStatus { stats?.status ?? .offline }
    private var ramCeiling: Double? { server.maxMemoryBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AdaptiveStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(server.serverName).font(.title2.weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                    AdaptiveStack(spacing: 10) {
                        Text(stats?.version ?? server.type.label).font(.subheadline).foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        StatusPill(status: status)
                    }
                }
                // Longer translations of the link below wrap before the version and status do.
                .layoutPriority(1)
                Spacer(minLength: 8)
                NavigationLink(value: DashboardRoute.detail(server)) {
                    HStack(spacing: 4) {
                        Text("Last 60 min")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Server details")
            }
            AdaptiveStack(alignment: .top, spacing: 16) {
                MetricColumn(title: "CPU", value: cpuText, caption: nil, color: Theme.cpu,
                             samples: history.map { ($0.date, $0.cpu) }, ceiling: 100, axis: .leading,
                             label: { "\(Int($0)) %" })
                Rectangle().fill(Theme.divider)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 1, height: typeSize.isAccessibilitySize ? 1 : nil)
                    .padding(typeSize.isAccessibilitySize ? .horizontal : .vertical, 4)
                MetricColumn(title: "RAM", value: ramText, caption: ramCeiling.map { String(localized: "of \(Self.gigabytes($0))") },
                             color: Theme.ram, samples: history.map { ($0.date, $0.memBytes) },
                             ceiling: ramCeiling ?? max(history.map(\.memBytes).max() ?? 0, 1), axis: .trailing,
                             label: { Self.gigabytes($0) })
            }
        }
        .card(padding: 20)
    }

    private var cpuText: String { stats?.running == true ? "\(Int((stats?.cpu ?? 0).rounded())) %" : "–" }

    private var ramText: String {
        guard stats?.running == true, let bytes = stats?.memBytes else { return "–" }
        return Self.gigabytes(bytes)
    }

    static func gigabytes(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        let number = gb >= 10 ? gb.rounded() : gb
        return number.formatted(.number.precision(.fractionLength(0...1))) + " GB"
    }
}

/// A capsule with the status color.
struct StatusPill: View {
    let status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(for: status)).frame(width: 8, height: 8)
            Text(status.label).font(.subheadline.weight(.medium)).lineLimit(1)
        }
        .fixedSize()
        .foregroundStyle(Theme.color(for: status))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.color(for: status).opacity(0.14), in: Capsule())
    }
}

/// A big current value and its last hour as an area chart.
struct MetricColumn: View {
    let title: LocalizedStringResource
    let value: String
    let caption: String?
    let color: Color
    let samples: [(date: Date, value: Double)]
    let ceiling: Double
    let axis: AxisMarkPosition
    let label: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            AdaptiveStack(alignment: .firstTextBaseline) {
                Text(value).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let caption { Text(caption).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(1) }
            }
            chart.frame(height: 96)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(caption.map { "\(value) \($0)" } ?? value)
    }

    @ViewBuilder private var chart: some View {
        let end = Date.now
        Chart {
            ForEach(samples, id: \.date) { s in
                AreaMark(x: .value("Time", s.date), y: .value(String(localized: title), min(s.value, ceiling)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.date), y: .value(String(localized: title), min(s.value, ceiling)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-DashboardModel.historyWindow)...end)
        .chartYScale(domain: 0...ceiling)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.divider)
            }
        }
        .chartYAxis {
            AxisMarks(position: axis, values: [0, ceiling / 2, ceiling]) { mark in
                AxisValueLabel {
                    if let v = mark.as(Double.self) { Text(label(v)).font(.caption2).foregroundStyle(Theme.secondaryText) }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.overlay {
                if samples.count < 2 {
                    Text("No data yet").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

/// Who is online, as pixel faces.
struct PlayersCard: View {
    let server: Server
    let stats: ServerStats?
    @ScaledMetric(relativeTo: .footnote) private var nameWidth: CGFloat = 72

    var body: some View {
        NavigationLink(value: DashboardRoute.players(server)) {
            VStack(alignment: .leading, spacing: 16) {
                AdaptiveStack(alignment: .firstTextBaseline) {
                    Text("Players").font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline) {
                        PlayerCount(online: stats?.online ?? 0, max: stats?.max ?? 0, large: true)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                    }
                }
                if let players = stats?.players, !players.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(players, id: \.self) { name in
                                VStack(spacing: 8) {
                                    PixelAvatar(name: name, size: 56)
                                    Text(name).font(.footnote).foregroundStyle(.primary).lineLimit(1).frame(maxWidth: nameWidth)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .scrollDisabled(players.count < 5)
                } else {
                    Text(stats?.running == true ? "Nobody is online." : "The server is not running.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            .card(padding: 20)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the player list")
    }
}

/// Console, and start or restart and stop, for the selected server.
struct ServerActionBar: View {
    let server: Server
    let status: ServerStatus
    let busy: ServerAction?
    let perform: (ServerAction) -> Void

    var body: some View {
        AdaptiveStack(spacing: 12) {
            NavigationLink(value: DashboardRoute.console(server)) {
                Label("Console", systemImage: "apple.terminal").frame(minHeight: 52)
            }
            .buttonStyle(InstrumentButtonStyle(kind: .console))
            switch status {
            case .online:
                button(.restart, "Restart", "arrow.clockwise", InstrumentButtonStyle())
                button(.stop, "Stop", "stop.fill", InstrumentButtonStyle(kind: .tinted, color: Theme.danger))
            case .offline, .crashed:
                button(.start, "Start", "play.fill", InstrumentButtonStyle())
            case .starting, .updating:
                Label(status.label, systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func button(_ action: ServerAction, _ title: LocalizedStringKey, _ symbol: String, _ style: InstrumentButtonStyle) -> some View {
        Button { perform(action) } label: {
            Group { if busy == action { ProgressView() } else { Label(title, systemImage: symbol) } }
                .frame(minHeight: 52)
        }
        .buttonStyle(style)
        .disabled(busy != nil)
    }
}

/// The selected server's latest console lines.
struct ConsolePreviewCard: View {
    let server: Server
    let lines: [String]

    var body: some View {
        NavigationLink(value: DashboardRoute.console(server)) {
            VStack(alignment: .leading, spacing: 12) {
                AdaptiveStack {
                    Text("Console").font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Show all")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.mono(.caption)).foregroundStyle(Theme.consoleText).lineLimit(1)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.console, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            }
            .card(padding: 20)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the console")
    }
}

/// Where the dashboard navigates.
enum DashboardRoute: Hashable {
    case detail(Server)
    case console(Server)
    case players(Server)
}
