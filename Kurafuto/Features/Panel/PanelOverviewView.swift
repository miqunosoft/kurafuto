import SwiftUI

/// Host overview: CPU/RAM/disk of the machine, panel version, announcements from the panel.
struct PanelOverviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var host: Loadable<HostStats> = .idle
    @State private var news: [Announcement] = []
    @State private var actionError: Error?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch host {
                    case .loaded(let h): hostSection(h).entrance(0)
                    case .failed(let e): StaleValuesBanner(problem: e.panelProblem)
                    case .idle, .loading: ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, minHeight: 160)
                    }
                    announcements.entrance(2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .themedBackground()
            .navigationTitle("Panel")
            .errorAlert($actionError)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func hostSection(_ h: HostStats) -> some View {
        VStack(spacing: 10) {
            SectionLabel("Host")
            AdaptiveStack(spacing: 10) {
                GaugeTile(title: "CPU", value: h.cpuPercent, color: Theme.cpu, delay: 0.2)
                GaugeTile(title: "RAM", value: h.memPercent, color: Theme.ram, delay: 0.3)
                ValueTile(title: "Panel", value: h.craftyVersion)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !h.diskUsage.isEmpty {
                VStack(spacing: 14) {
                    ForEach(h.diskUsage) { d in
                        VStack(alignment: .leading, spacing: 8) {
                            AdaptiveStack {
                                Label(d.mount, systemImage: "internaldrive").font(.mono(.footnote, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(verbatim: "\(Int(d.usedGB)) / \(Int(d.totalGB)) GB")
                                    .font(.mono(.caption)).foregroundStyle(Theme.secondaryText)
                            }
                            MeterBar(value: d.usedGB, total: d.totalGB, color: Theme.storage)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
                .entrance(1)
            }
        }
    }

    private var announcements: some View {
        VStack(spacing: 10) {
            SectionLabel("Announcements")
            if news.isEmpty {
                Text("No new announcements")
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            }
            ForEach(news) { n in
                HStack(alignment: .top, spacing: 12) {
                    IconTile(symbol: "megaphone.fill", color: Theme.accent, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.title).font(.headline)
                        Text(n.desc).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        Text(n.date).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task {
                            guard await $actionError.capture({ try await app.service.clearAnnouncement(id: n.id) }) else { return }
                            withAnimation(.snappy) { news.removeAll { $0.id == n.id } }
                        }
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Dismiss \(n.title)")
                }
                .card()
                .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }

    private func load() async {
        do { host = .loaded(try await app.service.hostStats()) }
        catch { host = .failed(error) }
        // Announcements are optional extras; without them the section simply stays empty.
        news = (try? await app.service.announcements()) ?? []
    }
}

#Preview { PanelOverviewView().environment(AppState.preview) }
