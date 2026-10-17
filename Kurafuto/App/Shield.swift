import SwiftUI
import UIKit

/// What covers the app: the app-switcher cover while the scene is not active, else the lock screen while locked.
enum Shield: Equatable {
    case cover, lock

    static func current(phase: ScenePhase, isLocked: Bool) -> Shield? {
        if phase != .active { return .cover }
        return isLocked ? .lock : nil
    }
}

/// Shows the shield in a window of its own above the app's. iOS presents sheets, alerts and confirmation
/// dialogs above the app's root view, so an overlay there would leave an open editor visible in the app
/// switcher and usable while the app is locked.
@MainActor
final class ShieldWindow {
    private var window: UIWindow?

    func show(_ shield: Shield?, app: AppState) {
        guard let shield,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            window?.isHidden = true
            window = nil
            return
        }
        let content = AnyView(ShieldView(shield: shield).environment(app))
        let window = self.window ?? UIWindow(windowScene: scene)
        if let host = window.rootViewController as? UIHostingController<AnyView> {
            host.rootView = content
        } else {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            // VoiceOver stays on the shield instead of reading the app or a sheet behind it.
            host.view.accessibilityViewIsModal = true
            window.rootViewController = host
        }
        window.windowLevel = .alert + 1
        window.isHidden = false
        self.window = window
    }
}

private struct ShieldView: View {
    let shield: Shield

    var body: some View {
        Group {
            switch shield {
            case .lock: LockView()
            // Hides panel addresses, IPs and console output from the app switcher snapshot.
            case .cover:
                ZStack {
                    Rectangle().fill(Theme.background)
                    Image(systemName: "cube.transparent.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Appearance.shared.mode.colorScheme)
    }
}
