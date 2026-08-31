import Cocoa

typealias CGWindowInfo = [String: Any]

struct CGWindowHit: Equatable {
    let ownerPID: pid_t
    let frame: CGRect
    let title: String?
}

struct AXWindowMatchCandidate: Equatable {
    let frame: CGRect?
    let title: String?
}

func onScreenWindowInfo() -> [CGWindowInfo] {
    CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [CGWindowInfo] ?? []
}

func frontmostWindow(
    at position: CGPoint,
    in windowInfo: [CGWindowInfo],
    ownedBy ownerPID: pid_t
) -> CGWindowHit? {
    for info in windowInfo {
        guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary else {
            continue
        }

        var frame = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &frame),
              frame.contains(position) else {
            continue
        }

        return CGWindowHit(
            ownerPID: ownerPID,
            frame: frame,
            title: info[kCGWindowName as String] as? String
        )
    }

    return nil
}

func matchingWindowIndex(
    for hit: CGWindowHit,
    candidates: [AXWindowMatchCandidate],
    tolerance: CGFloat = 2
) -> Int? {
    if let frameMatch = candidates.firstIndex(where: {
        guard let frame = $0.frame else { return false }
        return abs(frame.origin.x - hit.frame.origin.x) <= tolerance
            && abs(frame.origin.y - hit.frame.origin.y) <= tolerance
            && abs(frame.size.width - hit.frame.size.width) <= tolerance
            && abs(frame.size.height - hit.frame.size.height) <= tolerance
    }) {
        return frameMatch
    }

    guard let title = hit.title, !title.isEmpty else { return nil }
    return candidates.firstIndex { $0.title == title }
}


extension AXUIElement {

    private func canSet(_ attribute: NSAccessibility.Attribute) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private var processIdentifier: pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(self, &pid) == .success else { return nil }
        return pid
    }

    private var windowFrame: CGRect? {
        guard let origin, let size else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private var windowTitle: String? {
        var value: CFTypeRef?
        let result = withUnsafeMutablePointer(to: &value) { valuePtr in
            AXUIElementCopyAttributeValue(
                self,
                NSAccessibility.Attribute.title as CFString,
                valuePtr
            )
        }
        guard result == .success else { return nil }
        return value as? String
    }

    class func window(at position: CGPoint) -> AXUIElement? {
        window(
            at: position,
            windowInfoProvider: onScreenWindowInfo,
            accessibilityWindowProvider: accessibilityWindow,
            accessibilityHitTest: windowUsingAccessibilityHitTest
        )
    }

    class func window(
        at position: CGPoint,
        windowInfoProvider: () -> [CGWindowInfo],
        accessibilityWindowProvider: (CGWindowHit) -> AXUIElement?,
        accessibilityHitTest: (CGPoint) -> AXUIElement?
    ) -> AXUIElement? {
        guard let hitTestWindow = accessibilityHitTest(position),
              let ownerPID = hitTestWindow.processIdentifier,
              ownerPID != getpid() else {
            return nil
        }

        if let hit = frontmostWindow(
            at: position,
            in: windowInfoProvider(),
            ownedBy: ownerPID
        ),
        let matchedWindow = accessibilityWindowProvider(hit) {
            return matchedWindow
        }

        return hitTestWindow
    }

    private class func accessibilityWindow(matching hit: CGWindowHit) -> AXUIElement? {
        let application = AXUIElementCreateApplication(hit.ownerPID)
        let timeoutResult = AXUIElementSetMessagingTimeout(application, 0.5)
        guard timeoutResult == .success else {
            log(.debug, "Could not set Accessibility messaging timeout: \(timeoutResult.rawValue)")
            return nil
        }

        var value: CFTypeRef?
        let windowsResult = withUnsafeMutablePointer(to: &value) { valuePtr in
            AXUIElementCopyAttributeValue(
                application,
                NSAccessibility.Attribute.windows as CFString,
                valuePtr
            )
        }
        guard windowsResult == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }

        let candidates = windows.map { window in
            guard AXUIElementSetMessagingTimeout(window, 0.5) == .success else {
                return AXWindowMatchCandidate(frame: nil, title: nil)
            }
            return AXWindowMatchCandidate(frame: window.windowFrame, title: window.windowTitle)
        }
        guard let matchIndex = matchingWindowIndex(for: hit, candidates: candidates) else {
            return nil
        }
        return windows[matchIndex]
    }

    private class func windowUsingAccessibilityHitTest(at position: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        var selected: AXUIElement?
        let systemwideElement = AXUIElementCreateSystemWide()
        let timeoutResult = AXUIElementSetMessagingTimeout(systemwideElement, 0.5)
        if timeoutResult != .success {
            log(.debug, "Could not set Accessibility messaging timeout: \(timeoutResult.rawValue)")
            return nil
        }

        withUnsafeMutablePointer(to: &element) { elementPtr in
            guard AXUIElementCopyElementAtPosition(
                systemwideElement,
                Float(position.x),
                Float(position.y),
                elementPtr
            ) == .success,
            let element = elementPtr.pointee else { return }

            var role: CFTypeRef?
            let roleResult = withUnsafeMutablePointer(to: &role) { rolePtr in
                AXUIElementCopyAttributeValue(element, NSAccessibility.Attribute.role as CFString, rolePtr)
            }
            if roleResult == .success,
               let role = role as? NSAccessibility.Role,
               role == .window {
                selected = element
            }

            var window: CFTypeRef?
            let windowResult = withUnsafeMutablePointer(to: &window) { windowPtr in
                AXUIElementCopyAttributeValue(element, NSAccessibility.Attribute.window as CFString, windowPtr)
            }
            if windowResult == .success,
               let window,
               CFGetTypeID(window) == AXUIElementGetTypeID() {
                // The CF type ID check makes this bridge safe without an unchecked cast.
                selected = unsafeBitCast(window, to: AXUIElement.self)
            }
        }

        return selected
    }


    var origin: CGPoint? {
        get {
            var pos = CGPoint.zero

            var ref: CFTypeRef?
            let success = withUnsafeMutablePointer(to: &ref) { refPtr -> Bool in
                switch AXUIElementCopyAttributeValue(self, NSAccessibility.Attribute.position as CFString, refPtr) {
                case .success:
                    guard let ref = refPtr.pointee,
                          CFGetTypeID(ref) == AXValueGetTypeID() else { break }
                    // The CF type ID check makes this bridge safe without an unchecked cast.
                    let value = unsafeBitCast(ref, to: AXValue.self)
                    guard AXValueGetType(value) == .cgPoint else { break }
                    let success = withUnsafeMutablePointer(to: &pos) { ptr in
                        AXValueGetValue(value, .cgPoint, ptr)
                    }
                    if !success {
                        log(.debug, "ERROR: Could not decode position")
                    }
                    return success
                default:
                    break
                }
                return false
            }

            return success ? pos : nil
        }
        set {
            guard let newValue else { return }
            _ = setOrigin(newValue)
        }
    }

    func focus() {
        var processIdentifier: pid_t = 0
        if AXUIElementGetPid(self, &processIdentifier) == .success {
            NSRunningApplication(processIdentifier: processIdentifier)?.activate()
        }
        if AXUIElementPerformAction(self, NSAccessibility.Action.raise as CFString) != .success {
            log(.debug, "ERROR: failed to focus window")
        }
    }

    @discardableResult
    func setOrigin(_ newValue: CGPoint) -> Bool {
        let success = withUnsafePointer(to: newValue) { ptr -> Bool in
                if let position = AXValueCreate(.cgPoint, ptr) {
                    switch AXUIElementSetAttributeValue(self, NSAccessibility.Attribute.position as CFString, position) {
                    case .success:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            if !success {
                log(.debug, "ERROR: failed to set window origin")
            }
        return success
    }

    var isOriginSettable: Bool { canSet(.position) }


    var size: CGSize? {
        get {
            var size: CGSize = CGSize.zero

            var ref: CFTypeRef?
            let success = withUnsafeMutablePointer(to: &ref) { refPtr -> Bool in
                switch AXUIElementCopyAttributeValue(self, NSAccessibility.Attribute.size as CFString, refPtr) {
                case .success:
                    guard let ref = refPtr.pointee,
                          CFGetTypeID(ref) == AXValueGetTypeID() else { break }
                    // The CF type ID check makes this bridge safe without an unchecked cast.
                    let value = unsafeBitCast(ref, to: AXValue.self)
                    guard AXValueGetType(value) == .cgSize else { break }
                    let success = withUnsafeMutablePointer(to: &size) { sizePtr in
                        AXValueGetValue(value, .cgSize, sizePtr)
                    }
                    if !success {
                        log(.debug, "ERROR: Could not decode size")
                    }
                    return success
                default:
                    break
                }
                return false
            }

            return success ? size : nil
        }
        set {
            guard let newValue else { return }
            _ = setSize(newValue)
        }
    }

    @discardableResult
    func setSize(_ newValue: CGSize) -> Bool {
        let success = withUnsafePointer(to: newValue) { ptr -> Bool in
                if let size = AXValueCreate(.cgSize, ptr) {
                    switch AXUIElementSetAttributeValue(self, NSAccessibility.Attribute.size as CFString, size) {
                    case .success:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            if !success {
                log(.debug, "ERROR: failed to set window size")
            }
        return success
    }

    var isSizeSettable: Bool { canSet(.size) }

    var trackingWindow: TrackingWindow {
        TrackingWindow(
            origin: { [self] in origin },
            size: { [self] in size },
            canSetOrigin: { [self] in isOriginSettable },
            canSetSize: { [self] in isSizeSettable },
            focus: { [self] in focus() },
            setOrigin: { [self] value in setOrigin(value) },
            setSize: { [self] value in setSize(value) }
        )
    }

}
