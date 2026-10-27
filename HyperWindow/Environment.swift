import Foundation


private let sharedDefaults = UserDefaults(suiteName: "cloud.brett.HyperWindow.prefs") ?? .standard


struct Environment {
    var date: () -> Date = { Date() }
    // Must return one stable instance: Tracker observes didChangeNotification filtered by this object.
    var defaults: () -> UserDefaults = { sharedDefaults }
}


var Current = Environment()
