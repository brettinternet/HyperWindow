import AppKit
import XCTest
@testable import HyperWindow

@MainActor
final class PreferencesControllerTests: XCTestCase {
    func testAccessibilityStatusOnlyReservesSpaceWhenPermissionIsMissing() throws {
        let controller = PreferencesController(windowNibName: "ProgrammaticPreferences")
        _ = controller.window

        controller.updateAccessibilityStatus(trusted: false)
        let expandedSize = try XCTUnwrap(controller.window?.contentView?.frame.size)
        let expandedHeight = expandedSize.height
        let expandedTopEdge = try XCTUnwrap(controller.window).frame.maxY
        XCTAssertEqual(expandedSize.width, 390)
        XCTAssertFalse(controller.accessibilityStatusLabel.isHidden)
        XCTAssertFalse(controller.openSystemSettingsButton.isHidden)
        XCTAssertLessThanOrEqual(
            controller.openSystemSettingsButton.frame.maxY,
            controller.accessibilityStatusLabel.frame.minY
        )

        controller.updateAccessibilityStatus(trusted: true)
        let collapsedHeight = try XCTUnwrap(controller.window?.contentView?.frame.height)
        XCTAssertLessThan(collapsedHeight, expandedHeight)
        XCTAssertEqual(controller.window?.contentView?.frame.width, 390)
        XCTAssertEqual(controller.window?.frame.maxY, expandedTopEdge)
        XCTAssertTrue(controller.accessibilityStatusLabel.isHidden)
        XCTAssertTrue(controller.openSystemSettingsButton.isHidden)
    }

    func testModifierClickUpdatesStoredShortcut() throws {
        let defaults = testUserDefaults()
        registerDefaultPreferences(in: defaults)
        try Modifiers<Move>([.control, .fn]).save(forKey: .moveModifiers, defaults: defaults)
        try Modifiers<Resize>([.shift, .fn]).save(forKey: .resizeModifiers, defaults: defaults)

        let originalDefaults = Current.defaults
        Current.defaults = { defaults }
        defer { Current.defaults = originalDefaults }

        let controller = PreferencesController()
        let moveButtons = (0..<5).map { _ in NSButton() }
        let resizeButtons = (0..<5).map { _ in NSButton() }
        let resizeInfoLabel = NSTextField(labelWithString: "")
        let conflictLabel = NSTextField(labelWithString: "")
        let versionLabel = NSTextField(labelWithString: "")

        controller.moveAlt = moveButtons[0]
        controller.moveCommand = moveButtons[1]
        controller.moveControl = moveButtons[2]
        controller.moveFn = moveButtons[3]
        controller.moveShift = moveButtons[4]
        controller.resizeAlt = resizeButtons[0]
        controller.resizeCommand = resizeButtons[1]
        controller.resizeControl = resizeButtons[2]
        controller.resizeFn = resizeButtons[3]
        controller.resizeShift = resizeButtons[4]
        controller.resizeInfoLabel = resizeInfoLabel
        controller.modifierConflictLabel = conflictLabel
        controller.versionLabel = versionLabel

        controller.updateModifierButtonStates()
        XCTAssertEqual(moveButtons.map(\.state), [.off, .off, .on, .on, .off])
        XCTAssertEqual(resizeButtons.map(\.state), [.off, .off, .off, .on, .on])

        controller.updateCopy()
        controller.modifierClicked(resizeButtons[4])

        let updated = Modifiers<Resize>(forKey: .resizeModifiers, defaults: defaults)
        XCTAssertEqual(updated, [.fn])
    }

    func testPersistedPreferenceStatesAppearWhenWindowLoads() throws {
        let defaults = testUserDefaults()
        registerDefaultPreferences(in: defaults)
        defaults.set(true, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        defaults.set(false, forKey: DefaultsKeys.showMenuIcon.rawValue)
        defaults.set(true, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        defaults.set(true, forKey: DefaultsKeys.focusWindowOnManipulation.rawValue)

        let originalDefaults = Current.defaults
        Current.defaults = { defaults }
        defer { Current.defaults = originalDefaults }

        let controller = PreferencesController(windowNibName: "ProgrammaticPreferences")
        _ = controller.window

        XCTAssertTrue(controller.window?.delegate === controller)
        XCTAssertEqual(controller.resizeFromNearestCorner.state, .on)
        XCTAssertEqual(controller.showMenuIcon.state, .off)
        XCTAssertEqual(controller.requireDragToActivate.state, .on)
        XCTAssertEqual(controller.focusWindowOnManipulation.state, .on)
    }

    func testModifierConflictExpandsWindowImmediately() throws {
        let defaults = testUserDefaults()
        registerDefaultPreferences(in: defaults)
        try Modifiers<Move>([.control, .fn]).save(forKey: .moveModifiers, defaults: defaults)
        try Modifiers<Resize>([.control]).save(forKey: .resizeModifiers, defaults: defaults)

        let originalDefaults = Current.defaults
        Current.defaults = { defaults }
        defer { Current.defaults = originalDefaults }

        let controller = PreferencesController(windowNibName: "ProgrammaticPreferences")
        _ = controller.window
        let initialHeight = try XCTUnwrap(controller.window?.contentView?.frame.height)

        controller.modifierClicked(controller.resizeFn)

        XCTAssertFalse(controller.modifierConflictLabel.isHidden)
        XCTAssertGreaterThan(try XCTUnwrap(controller.window?.contentView?.frame.height), initialHeight)
    }

    func testFocusWindowPreferenceCanBeEnabledAndDisabled() {
        let defaults = testUserDefaults()
        registerDefaultPreferences(in: defaults)
        let originalDefaults = Current.defaults
        Current.defaults = { defaults }
        defer { Current.defaults = originalDefaults }

        let controller = PreferencesController()
        let focusButton = NSButton()
        controller.focusWindowOnManipulation = focusButton

        controller.focusWindowOnManipulationClicked(focusButton)
        XCTAssertTrue(defaults.bool(forKey: DefaultsKeys.focusWindowOnManipulation.rawValue))
        XCTAssertEqual(focusButton.state, .on)

        controller.focusWindowOnManipulationClicked(focusButton)
        XCTAssertFalse(defaults.bool(forKey: DefaultsKeys.focusWindowOnManipulation.rawValue))
        XCTAssertEqual(focusButton.state, .off)
    }

    func testSettingsUseConstraintBasedLayout() throws {
        let controller = PreferencesController(windowNibName: "ProgrammaticPreferences")
        _ = controller.window
        controller.updateAccessibilityStatus(trusted: false)

        let contentView = try XCTUnwrap(controller.window?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let controls = try [
            XCTUnwrap(controller.moveAlt),
            XCTUnwrap(controller.resizeAlt),
            XCTUnwrap(controller.resizeFromNearestCorner),
            XCTUnwrap(controller.showMenuIcon),
            XCTUnwrap(controller.launchAtLogin),
            XCTUnwrap(controller.requireDragToActivate),
            XCTUnwrap(controller.focusWindowOnManipulation)
        ]
        XCTAssertEqual(contentView.frame.width, 390)
        XCTAssertTrue(controls.allSatisfy { !$0.translatesAutoresizingMaskIntoConstraints })
        XCTAssertTrue(controls.allSatisfy { contentView.convert($0.bounds, from: $0).width > 0 })
        XCTAssertTrue(controls.allSatisfy { contentView.convert($0.bounds, from: $0).maxX <= contentView.bounds.maxX })
    }

    func testFormattedVersionFormatsShortAndFullVersions() {
        XCTAssertEqual(formattedVersion(shortVersion: "1.2.3", bundleVersion: "42", short: true), "1.2.3")
        XCTAssertEqual(formattedVersion(shortVersion: "1.2.3", bundleVersion: "42"), "1.2.3 (42)")
    }

    func testSettingsVersionIncludesCommitForUntaggedBuild() {
        let version = settingsVersion(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3",
            "GitCommit": "abc1234"
        ])

        XCTAssertEqual(version, "1.2.3 (abc1234)")
    }

    func testSettingsVersionOmitsCommitForTaggedBuild() {
        let version = settingsVersion(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3"
        ])

        XCTAssertEqual(version, "1.2.3")
    }
}
