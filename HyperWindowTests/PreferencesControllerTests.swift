import AppKit
import XCTest
@testable import HyperWindow

@MainActor
final class PreferencesControllerTests: XCTestCase {
    func testAccessibilityStatusOnlyReservesSpaceWhenPermissionIsMissing() throws {
        let controller = PreferencesController(windowNibName: "PreferencesController")
        controller.loadWindow()

        controller.updateAccessibilityStatus(trusted: false)
        XCTAssertEqual(controller.window?.contentView?.frame.size, NSSize(width: 390, height: 308))
        let expandedTopEdge = try XCTUnwrap(controller.window).frame.maxY
        XCTAssertFalse(controller.accessibilityStatusLabel.isHidden)
        XCTAssertFalse(controller.openSystemSettingsButton.isHidden)
        XCTAssertLessThanOrEqual(
            controller.openSystemSettingsButton.frame.maxY,
            controller.accessibilityStatusLabel.frame.minY
        )

        controller.updateAccessibilityStatus(trusted: true)
        XCTAssertEqual(controller.window?.contentView?.frame.size, NSSize(width: 390, height: 256))
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

    func testGeneralCheckboxRowsAlignWithShortcutRows() throws {
        let controller = PreferencesController(windowNibName: "PreferencesController")
        controller.loadWindow()
        controller.updateAccessibilityStatus(trusted: false)

        let contentView = try XCTUnwrap(controller.window?.contentView)
        let moveTop = try XCTUnwrap(controller.moveAlt)
        let resizeTop = try XCTUnwrap(controller.resizeAlt)
        let moveTopY = contentView.convert(moveTop.bounds, from: moveTop).minY
        let resizeTopY = contentView.convert(resizeTop.bounds, from: resizeTop).minY

        let generalRows = try [
            XCTUnwrap(controller.resizeFromNearestCorner),
            XCTUnwrap(controller.showMenuIcon),
            XCTUnwrap(controller.launchAtLogin),
            XCTUnwrap(controller.requireDragToActivate),
            XCTUnwrap(controller.focusWindowOnManipulation)
        ]
        let generalRowYs = generalRows.map {
            contentView.convert($0.bounds, from: $0).minY
        }
        XCTAssertEqual(moveTopY, generalRowYs[0], accuracy: 0.001)
        XCTAssertEqual(resizeTopY, generalRowYs[0], accuracy: 0.001)
        XCTAssertEqual(
            zip(generalRowYs, generalRowYs.dropFirst()).map { $0.0 - $0.1 },
            [26, 25, 25, 26]
        )
    }
}
