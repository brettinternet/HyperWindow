import XCTest
@testable import HyperWindow


class AppStateMachineTests: XCTestCase {

    override func tearDown() {
        Tracker.disable()
    }

}


class AppDelegateLaunchTests: XCTestCase {

    func test_login_launch_is_not_a_manual_launch() {
        XCTAssertTrue(AppDelegate.isManualLaunch(launchedAsLoginItem: false))
        XCTAssertFalse(AppDelegate.isManualLaunch(launchedAsLoginItem: true))
    }

    func test_statusPresentationRequires_tracker_permission_and_activated_state() {
        XCTAssertTrue(AppDelegate.statusIsActive(state: .activated, trackerIsActive: true, isTrusted: true))
        XCTAssertFalse(AppDelegate.statusIsActive(state: .activated, trackerIsActive: false, isTrusted: true))
        XCTAssertFalse(AppDelegate.statusIsActive(state: .activated, trackerIsActive: true, isTrusted: false))
        XCTAssertFalse(AppDelegate.statusIsActive(state: .deactivated, trackerIsActive: true, isTrusted: true))
    }

    func test_permissionTransition_classifies_grant_revoke_and_unchanged() {
        XCTAssertEqual(AppDelegate.permissionTransition(from: false, to: true), .granted)
        XCTAssertEqual(AppDelegate.permissionTransition(from: true, to: false), .revoked)
        XCTAssertEqual(AppDelegate.permissionTransition(from: false, to: false), .unchanged)
        XCTAssertEqual(AppDelegate.permissionTransition(from: true, to: true), .unchanged)
    }

    func test_statusPresentation_policy_reflects_menu_checked_dim_and_permission_state() {
        let active = AppDelegate.statusPresentation(state: .activated, trackerIsActive: true, isTrusted: true)
        XCTAssertTrue(active.isActive)
        XCTAssertTrue(active.menuChecked)
        XCTAssertEqual(active.iconAlpha, 1.0)
        XCTAssertEqual(active.accessibilityValue, "Enabled")
        XCTAssertTrue(AppDelegate.shouldHidePermissionStatusMenuItem(isTrusted: true))

        let paused = AppDelegate.statusPresentation(state: .activated, trackerIsActive: false, isTrusted: true)
        XCTAssertFalse(paused.isActive)
        XCTAssertFalse(paused.menuChecked)
        XCTAssertEqual(paused.iconAlpha, 0.45)
        XCTAssertEqual(paused.accessibilityValue, "Paused")

        let unavailable = AppDelegate.statusPresentation(state: .activated, trackerIsActive: true, isTrusted: false)
        XCTAssertFalse(unavailable.isActive)
        XCTAssertFalse(unavailable.menuChecked)
        XCTAssertEqual(unavailable.iconAlpha, 0.45)
        XCTAssertEqual(unavailable.accessibilityValue, "Accessibility permission required")
        XCTAssertFalse(AppDelegate.shouldHidePermissionStatusMenuItem(isTrusted: false))
    }

    func test_xctest_host_does_not_start_runtime_services() {
        XCTAssertTrue(AppDelegate.isUnitTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]))
        XCTAssertFalse(AppDelegate.isUnitTestHost(environment: [:]))
    }

    func test_settings_menu_item_uses_command_comma_and_opens_settings_window() {
        guard let app = NSApp else {
            XCTFail("Hosted XCTest app is unavailable")
            return
        }
        guard let appDelegate = app.delegate as? AppDelegate else {
            XCTFail("Hosted XCTest app delegate is unavailable")
            return
        }
        guard let mainMenu = app.mainMenu else {
            XCTFail("Hosted XCTest main menu is unavailable")
            return
        }
        guard let settingsItem = menuItem(title: "Settings…", keyEquivalent: ",", in: mainMenu) else {
            XCTFail("Command-Comma Settings menu item is unavailable")
            return
        }

        XCTAssertTrue(settingsItem.keyEquivalentModifierMask.contains(.command))
        guard let action = settingsItem.action else {
            XCTFail("Settings menu item action is unavailable")
            return
        }
        XCTAssertEqual(action, #selector(AppDelegate.showPreferences(_:)))
        XCTAssertTrue(settingsItem.target === appDelegate)

        XCTAssertTrue(app.sendAction(action, to: settingsItem.target, from: settingsItem))
        defer { appDelegate.preferencesController.window?.close() }
        XCTAssertTrue(appDelegate.preferencesController.window?.isVisible == true)
    }

    func test_enabled_toggle_deactivates_active_tracker() {
        let app = AppStateMachine(initialState: .activated)
        app.toggleEnabled()
        XCTAssertEqual(app.state, .deactivated)
        XCTAssertFalse(Tracker.isActive)
    }

    func test_login_item_open_event_is_detected() {
        let event = openApplicationEvent()
        event.setParam(
            NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem),
            forKeyword: keyAEPropData
        )

        XCTAssertTrue(isLoginItemLaunch(event))
    }

    func test_manual_open_event_is_not_detected_as_login_item() {
        XCTAssertFalse(isLoginItemLaunch(openApplicationEvent()))
    }

    func test_missing_launch_event_is_not_detected_as_login_item() {
        XCTAssertFalse(isLoginItemLaunch(nil))
    }

    private func openApplicationEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    private func menuItem(title: String, keyEquivalent: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title && item.keyEquivalent == keyEquivalent {
                return item
            }
            if let submenu = item.submenu, let match = menuItem(title: title, keyEquivalent: keyEquivalent, in: submenu) {
                return match
            }
        }
        return nil
    }
}


// MARK:- Helpers


let trackerIsActive = NSPredicate { (_, _) in
    Tracker.isActive
}


let trackerIsNotActive = NSPredicate { (_, _) in
    !Tracker.isActive
}


func testUserDefaults(firstLaunched: Date?) throws -> UserDefaults {
    let def = testUserDefaults()
    if let firstLaunched = firstLaunched {
        try firstLaunched.save(forKey: .firstLaunched, defaults: def)
    }
    return def
}


class TestAppDelegate {
    var stateMachine = AppStateMachine()

    var transitions = [(from: AppStateMachine.State, to: AppStateMachine.State)]()

    func applicationDidFinishLaunching() {
        stateMachine.delegate = self
        XCTAssertEqual(stateMachine.state, .launching)
        XCTAssert(!Tracker.isActive)
        stateMachine.state = .validatingState
    }
}

extension TestAppDelegate: DidTransitionDelegate {
    func didTransition(from: AppStateMachine.State, to: AppStateMachine.State) {
        transitions.append((from, to))
    }
}
