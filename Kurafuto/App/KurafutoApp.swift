import SwiftUI

@main
struct KurafutoApp: App {
    @State private var app: AppState

    init() {
        let state = AppState.bootstrap()
        _app = State(initialValue: state)
        ServerShortcuts.app = state
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

/// Global state: active instance + service. The whole UI depends only on `service: CraftyService`.
@Observable
final class AppState {
    var instanceStore: InstanceStore
    var activeInstance: Instance?
    var service: CraftyService
    var isMock: Bool
    let lock: AppLock
    /// Panel-wide rights of the signed-in user; nil until loaded or when loading failed.
    var access: PanelAccess?
    /// The panel rejected the active token; RootView asks to sign in again.
    var sessionExpired = false
    /// A widget asked to show this server (or its console or details); the Servers tab opens it once it lists it.
    var requestedServer: ServerLink.Target?

    init(instanceStore: InstanceStore, service: CraftyService, activeInstance: Instance?, isMock: Bool,
         lock: AppLock = AppLock()) {
        self.instanceStore = instanceStore
        self.lock = lock
        self.service = service
        self.activeInstance = activeInstance
        self.isMock = isMock
    }

    static func bootstrap() -> AppState {
        if ProcessInfo.processInfo.arguments.contains("-mock") {
            return .demo(lock: AppLock())
        }
        let store = InstanceStore()
        let first = store.instances.first
        let service: CraftyService = first.map { inst in
            LiveCraftyService(client: APIClient(baseURL: inst.baseURL, token: store.token(for: inst),
                                                pinnedSHA256: inst.pinnedCertificateSHA256))
        } ?? MockCraftyService()
        return AppState(instanceStore: store, service: service, activeInstance: first, isMock: first == nil)
    }

    static var preview: AppState { .demo(lock: AppLock(defaults: nil)) }

    private static func demo(lock: AppLock) -> AppState {
        AppState(instanceStore: InstanceStore(preview: [MockData.instance]),
                 service: MockCraftyService(latency: .milliseconds(250)),
                 activeInstance: MockData.instance, isMock: true, lock: lock)
    }

    func switchTo(_ instance: Instance) {
        // Re-selecting the active panel must not rebuild the service: in demo mode that would
        // replace the mock with a live client pointed at the sample address.
        guard instance.id != activeInstance?.id else { return }
        activeInstance = instance
        access = nil
        WidgetSync.clear()
        service = LiveCraftyService(client: APIClient(baseURL: instance.baseURL,
                                                      token: instanceStore.token(for: instance),
                                                      pinnedSHA256: instance.pinnedCertificateSHA256))
        isMock = false
    }

    func startDemo() {
        activeInstance = MockData.instance
        access = nil
        service = MockCraftyService()
        isMock = true
    }

    /// A server page of the active panel's web UI, for what the API cannot do. Built from the stored panel
    /// address and the server's id only.
    func webPanelURL(serverID: String, subpage: String) -> URL? {
        guard let base = activeInstance?.baseURL,
              var comps = URLComponents(url: base.appending(path: "/panel/server_detail"), resolvingAgainstBaseURL: false),
              comps.scheme?.lowercased() == "https" else { return nil }
        comps.queryItems = [URLQueryItem(name: "id", value: serverID), URLQueryItem(name: "subpage", value: subpage)]
        return comps.url
    }

    /// Only the active panel's client counts: onboarding and sign-in checks use their own clients.
    func isActiveClient(_ object: Any?) -> Bool {
        guard let client = object as? APIClient else { return false }
        return (service as? LiveCraftyService)?.client === client
    }

    func reauthenticate(_ instance: Instance, token: String) {
        instanceStore.upsert(instance, token: token)
        activeInstance = instance
        access = nil
        service = LiveCraftyService(client: APIClient(baseURL: instance.baseURL, token: token,
                                                      pinnedSHA256: instance.pinnedCertificateSHA256))
        sessionExpired = false
    }

    func signOut() {
        if let i = activeInstance, !isMock { instanceStore.remove(i) }
        activeInstance = nil
        access = nil
        WidgetSync.clear()
    }
}

extension AppState {
    @MainActor
    func refreshAccess() async {
        access = try? await service.panelAccess()
    }

    // While the rights are unknown, the UI stays complete: the panel enforces them on every request
    // and its errors are shown, which beats hiding the Admin tab from a superuser on a slow network.
    var canCreateServers: Bool { access?.canCreateServers ?? true }
    var canAddUsers: Bool { access?.canAddUsers ?? true }
    var canAddRoles: Bool { access?.canAddRoles ?? true }
    var canManageUsers: Bool { access?.canManageUsers ?? true }
    var canManageRoles: Bool { access?.canManageRoles ?? true }
    var showsAdmin: Bool { access?.showsAdmin ?? true }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.activeInstance == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .accessibilityHidden(app.lock.isLocked)
        .overlay { if app.lock.isLocked { LockView() } }
        .sheet(isPresented: Binding(get: { app.sessionExpired && !app.lock.isLocked && !app.isMock },
                                    set: { app.sessionExpired = $0 })) {
            SignInAgainView()
        }
        .task {
            for await note in NotificationCenter.default.notifications(named: .panelSessionExpired)
            where app.isActiveClient(note.object) {
                app.sessionExpired = true
            }
        }
        .onOpenURL { url in
            if let target = ServerLink.target(from: url) { app.requestedServer = target }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Appearance.shared.mode.colorScheme)
        // Hides panel addresses, IPs and console output from the app switcher snapshot.
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(Theme.background)
                    Image(systemName: "cube.transparent.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
                }
                .ignoresSafeArea()
            }
        }
        // Lock on .background only: the Face ID prompt itself makes the scene .inactive.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.lock.lockIfEnabled() }
            if phase == .active { Task { await app.lock.unlock() } }
        }
        .task { await app.lock.unlock() }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @State private var tab = Tab.servers

    enum Tab { case servers, panel, admin, settings }

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("Servers", systemImage: "server.rack") }
                .tag(Tab.servers)
            PanelOverviewView()
                .tabItem { Label("Panel", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.panel)
            if app.showsAdmin {
                AdminView()
                    .tabItem { Label("Admin", systemImage: "shield.lefthalf.filled") }
                    .tag(Tab.admin)
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: app.requestedServer) { _, target in if target != nil { tab = .servers } }
        .task(id: ObjectIdentifier(app.service)) { await app.refreshAccess() }
    }
}

#Preview { RootView().environment(AppState.preview) }
