import Foundation


enum DefaultsKeys: String {
    case firstLaunched
    case moveModifiers
    case resizeModifiers
    case resizeFromNearestCorner
    case showMenuIcon
    case launchAtLogin
    case focusWindowOnManipulation
    case requireDragToActivate
}


let DefaultPreferences = [
    DefaultsKeys.moveModifiers.rawValue: Modifiers<Move>.defaultValue,
    DefaultsKeys.resizeModifiers.rawValue: Modifiers<Resize>.defaultValue,
    DefaultsKeys.showMenuIcon.rawValue: NSNumber.init(booleanLiteral: true),
    DefaultsKeys.launchAtLogin.rawValue: NSNumber.init(booleanLiteral: false),
    DefaultsKeys.requireDragToActivate.rawValue: NSNumber.init(booleanLiteral: false),
    DefaultsKeys.focusWindowOnManipulation.rawValue: NSNumber.init(booleanLiteral: false)
]


func registerDefaultPreferences(in defaults: UserDefaults = Current.defaults()) {
    defaults.register(defaults: DefaultPreferences)
}


protocol Defaultable {
    init?(forKey: DefaultsKeys, defaults: UserDefaults)
    func save(forKey: DefaultsKeys, defaults: UserDefaults) throws
}
