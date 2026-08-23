import XCTest
@testable import HyperWindow


final class DefaultsTests: XCTestCase {
    func test_registers_menu_icon_as_enabled_by_default() {
        let defaults = testUserDefaults()

        registerDefaultPreferences(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: DefaultsKeys.showMenuIcon.rawValue))
        XCTAssertFalse(defaults.bool(forKey: DefaultsKeys.focusWindowOnManipulation.rawValue))
    }

    func test_registers_shortcut_defaults() {
        let defaults = testUserDefaults()

        registerDefaultPreferences(in: defaults)

        XCTAssertEqual(
            Modifiers<Move>(forKey: .moveModifiers, defaults: defaults),
            [.control, .fn]
        )
        XCTAssertEqual(
            Modifiers<Resize>(forKey: .resizeModifiers, defaults: defaults),
            [.control, .fn, .shift]
        )
    }

    func test_persisted_menu_icon_preference_overrides_registered_default() {
        let defaults = testUserDefaults()
        defaults.set(false, forKey: DefaultsKeys.showMenuIcon.rawValue)

        registerDefaultPreferences(in: defaults)

        XCTAssertFalse(defaults.bool(forKey: DefaultsKeys.showMenuIcon.rawValue))
    }
}
