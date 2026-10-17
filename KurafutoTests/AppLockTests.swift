import XCTest
@testable import Kurafuto

@MainActor
final class AppLockTests: XCTestCase {
    private final class FakeAuthenticator: DeviceAuthenticating, @unchecked Sendable {
        var deviceKind: DeviceAuthKind = .faceID
        var answers: [Bool] = []
        private(set) var reasons: [String] = []
        func kind() -> DeviceAuthKind { deviceKind }
        func authenticate(reason: String) async -> Bool {
            reasons.append(reason)
            return answers.isEmpty ? false : answers.removeFirst()
        }
    }

    private func freshDefaults() throws -> UserDefaults {
        let suite = "AppLockTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func enabledLock(_ auth: FakeAuthenticator, _ defaults: UserDefaults) -> AppLock {
        defaults.set(true, forKey: AppLock.defaultsKey)
        return AppLock(authenticator: auth, defaults: defaults)
    }

    func testOffByDefaultAndNeverPrompts() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        let lock = AppLock(authenticator: auth, defaults: defaults)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)
        let allowed = await lock.authorize("Stop server?")
        XCTAssertTrue(allowed)
        await lock.unlock()
        XCTAssertEqual(auth.reasons, [])
    }

    func testEnabledLockStartsLockedAndUnlocksOnSuccess() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        let lock = enabledLock(auth, defaults)
        XCTAssertTrue(lock.isLocked)

        auth.answers = [false]
        await lock.unlock()
        XCTAssertTrue(lock.isLocked, "a failed or cancelled check keeps the app locked")

        auth.answers = [true]
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(auth.reasons, ["Unlock Kurafuto", "Unlock Kurafuto"])
    }

    func testBackgroundLocksAgainOnlyWhenEnabled() async throws {
        let defaults = try freshDefaults()
        let off = AppLock(authenticator: FakeAuthenticator(), defaults: defaults)
        off.lockIfEnabled()
        XCTAssertFalse(off.isLocked)

        let auth = FakeAuthenticator()
        auth.answers = [true]
        let on = enabledLock(auth, defaults)
        await on.unlock()
        on.lockIfEnabled()
        XCTAssertTrue(on.isLocked)
    }

    func testDestructiveActionsNeedAuthenticationWhenEnabled() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        auth.answers = [true]
        let lock = enabledLock(auth, defaults)
        await lock.unlock()

        auth.answers = [false, true]
        let denied = await lock.authorize("Kill process?")
        let allowed = await lock.authorize("Kill process?")
        XCTAssertFalse(denied)
        XCTAssertTrue(allowed)
        XCTAssertEqual(auth.reasons.suffix(2), ["Kill process?", "Kill process?"])
    }

    func testTurningOnAndOffNeedsAuthenticationAndPersists() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        let lock = AppLock(authenticator: auth, defaults: defaults)

        auth.answers = [false]
        await lock.setEnabled(true)
        XCTAssertFalse(lock.isEnabled)

        auth.answers = [true]
        await lock.setEnabled(true)
        XCTAssertTrue(lock.isEnabled)
        XCTAssertFalse(lock.isLocked, "turning it on does not lock the open app")
        XCTAssertTrue(defaults.bool(forKey: AppLock.defaultsKey))

        auth.answers = [false]
        await lock.setEnabled(false)
        XCTAssertTrue(lock.isEnabled, "someone else can't switch it off")

        auth.answers = [true]
        await lock.setEnabled(false)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppLock.defaultsKey))
    }

    func testCannotTurnOnWithoutDevicePasscode() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        auth.deviceKind = .unavailable
        auth.answers = [true]
        let lock = AppLock(authenticator: auth, defaults: defaults)
        await lock.setEnabled(true)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertEqual(auth.reasons, [])
    }

    func testRemovedPasscodeDoesNotLockUserOut() async throws {
        let defaults = try freshDefaults()
        let auth = FakeAuthenticator()
        auth.deviceKind = .unavailable
        let lock = enabledLock(auth, defaults)
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
    }

    func testShieldCoversWhileInactiveAndLocksWhileLocked() {
        XCTAssertEqual(Shield.current(phase: .inactive, isLocked: false), .cover)
        XCTAssertEqual(Shield.current(phase: .background, isLocked: true), .cover)
        XCTAssertEqual(Shield.current(phase: .active, isLocked: true), .lock)
        XCTAssertNil(Shield.current(phase: .active, isLocked: false))
    }

    /// Sheets and alerts are presented inside the app's window, so the shield needs a window above it.
    func testShieldWindowSitsAboveTheAppAndGoesAway() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let shieldLevel = UIWindow.Level.alert + 1
        func shields() -> [UIWindow] { scene.windows.filter { !$0.isHidden && $0.windowLevel == shieldLevel } }
        let window = ShieldWindow()

        window.show(.lock, app: AppState.preview)
        XCTAssertEqual(shields().count, 1)
        XCTAssertTrue(scene.windows.filter { $0 !== shields().first }.allSatisfy { $0.windowLevel < shieldLevel })

        window.show(.cover, app: AppState.preview)
        XCTAssertEqual(shields().count, 1)

        window.show(nil, app: AppState.preview)
        XCTAssertTrue(shields().isEmpty)
    }

    func testPreviewLockIsOffAndNotPersisted() {
        XCTAssertFalse(AppState.preview.lock.isEnabled)
        XCTAssertFalse(AppState.preview.lock.isLocked)
    }
}
