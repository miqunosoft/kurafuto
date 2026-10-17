import XCTest
@testable import Kurafuto

/// Tokens that iOS kept in the Keychain after the app was deleted go away with the next install.
final class ReinstallTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let suite = "ReinstallTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testFreshInstallDeletesOldTokensOnce() throws {
        let defaults = try freshDefaults()
        var deletions = 0
        InstanceStore.forgetEarlierInstall(listExists: false, defaults: defaults) { deletions += 1 }
        InstanceStore.forgetEarlierInstall(listExists: false, defaults: defaults) { deletions += 1 }
        XCTAssertEqual(deletions, 1)
        XCTAssertTrue(defaults.bool(forKey: InstanceStore.installedKey))
    }

    /// Also covers a launch before the first unlock, when the settings read as empty but the panel list exists.
    func testExistingPanelListKeepsTokens() throws {
        let defaults = try freshDefaults()
        var deletions = 0
        InstanceStore.forgetEarlierInstall(listExists: true, defaults: defaults) { deletions += 1 }
        XCTAssertEqual(deletions, 0)
    }

    func testLaterLaunchesKeepTokens() throws {
        let defaults = try freshDefaults()
        defaults.set(true, forKey: InstanceStore.installedKey)
        var deletions = 0
        InstanceStore.forgetEarlierInstall(listExists: false, defaults: defaults) { deletions += 1 }
        XCTAssertEqual(deletions, 0)
    }
}
