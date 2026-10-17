import SwiftUI

/// Live console with command input, quick commands and history.
struct ConsoleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let server: Server
    @State private var lines: [LogLine] = []
    @State private var input = ""
    @State private var history: [String] = []
    @State private var autoScroll = true
    @State private var filter = ""
    @State private var actionError: Error?
    @FocusState private var focused: Bool

    private let quick = ["list", "save-all", "weather clear", "time set day", "say Hello!", "whitelist list"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(visible) { line in
                            Text(line.text)
                                .font(.mono(.caption))
                                .foregroundStyle(color(line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                                                  removal: .opacity))
                        }
                    }
                    .padding(12)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: lines.last?.id)
                }
                .background(Theme.console)
                .onChange(of: lines.last?.id) {
                    if autoScroll, let last = lines.last { withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.self) { cmd in
                            Button(cmd) { Task { await send(cmd) } }
                                .font(.mono(.caption, weight: .medium))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(Theme.sunken, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.stroke))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                AdaptiveStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(verbatim: ">").font(.mono(.body, weight: .semibold)).foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        TextField("Command without /", text: $input)
                            .font(.mono(.body))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.send)
                            .onSubmit { Task { await send(input) } }
                        Menu {
                            ForEach(history.reversed().prefix(10), id: \.self) { h in Button(h) { input = h } }
                        } label: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.secondaryText) }
                        .disabled(history.isEmpty)
                        .accessibilityLabel("Command history")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))

                    Button { Task { await send(input) } } label: {
                        Image(systemName: "arrow.right").font(.body.weight(.bold))
                    }
                    .buttonStyle(InstrumentButtonStyle())
                    .frame(width: typeSize.isAccessibilitySize ? nil : 48)
                    .disabled(input.isEmpty)
                    .accessibilityLabel("Send command")
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Filter")
        .errorAlert($actionError)
        .toolbar {
            Toggle(isOn: $autoScroll) { Image(systemName: "arrow.down.to.line") }
                .accessibilityLabel("Auto-scroll")
            ShareLink(item: lines.map(\.text).joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
        }
        .task {
            for await line in app.service.consoleStream(serverID: server.id) {
                lines.append(line)
                if lines.count > CraftyConsoleFeed.memory { lines.removeFirst(lines.count - CraftyConsoleFeed.memory) }
            }
        }
    }

    private var visible: [LogLine] {
        filter.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    private func color(_ l: LogLine.Level) -> Color {
        switch l {
        case .info: Theme.consoleText
        case .warn: Theme.consoleWarning
        case .error: Theme.consoleError
        case .command: Theme.consoleCommand
        case .chat: Theme.consoleChat
        }
    }

    private func send(_ cmd: String) async {
        let c = cmd.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        input = ""
        history.append(c)
        await $actionError.capture { try await app.service.sendCommand(c, serverID: server.id) }
    }
}

/// Log file (latest.log) instead of stdout – with a problems-only filter.
struct LogsView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[String]> = .idle
    @State private var onlyProblems = false

    var body: some View {
        LoadableView(state: state, retry: load) { lines in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(shown(lines).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.mono(.caption2))
                            .foregroundStyle(line.contains("ERROR") ? Theme.consoleError
                                             : line.contains("WARN") ? Theme.consoleWarning
                                             : Theme.consoleText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .background(Theme.console)
            .entrance()
        }
        .background(Theme.console.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Toggle("Warnings only", isOn: $onlyProblems) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func shown(_ lines: [String]) -> [String] {
        lines.filter { !onlyProblems || $0.contains("WARN") || $0.contains("ERROR") }
    }

    private func load() async {
        do { state = .loaded(try await app.service.logs(serverID: server.id, fromFile: true)) }
        catch { state = .failed(error) }
    }
}

#Preview {
    NavigationStack { ConsoleView(server: MockData.servers[0]) }.environment(AppState.preview)
}
