import Cocoa
import ServiceManagement


class PreferencesController: NSWindowController {

    @IBOutlet weak var moveAlt: NSButton!
    @IBOutlet weak var moveCommand: NSButton!
    @IBOutlet weak var moveControl: NSButton!
    @IBOutlet weak var moveFn: NSButton!
    @IBOutlet weak var moveShift: NSButton!

    @IBOutlet weak var resizeAlt: NSButton!
    @IBOutlet weak var resizeCommand: NSButton!
    @IBOutlet weak var resizeControl: NSButton!
    @IBOutlet weak var resizeFn: NSButton!
    @IBOutlet weak var resizeShift: NSButton!

    @IBOutlet weak var resizeFromNearestCorner: NSButton!
    @IBOutlet weak var resizeInfoLabel: NSTextField!
    @IBOutlet weak var modifierConflictLabel: NSTextField!

    @IBOutlet weak var showMenuIcon: NSButton!
    @IBOutlet weak var launchAtLogin: NSButton!
    @IBOutlet weak var requireDragToActivate: NSButton!
    @IBOutlet weak var focusWindowOnManipulation: NSButton!

    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var accessibilityStatusLabel: NSTextField!
    @IBOutlet weak var openSystemSettingsButton: NSButton!
    @IBOutlet weak var githubLink: NSButton!
    
    override func windowDidLoad() {
        super.windowDidLoad()
        updateModifierButtonStates()
        updateFocusWindowPreferenceState()
        updateAccessibilityStatus()
        updateLaunchAtLoginState()
        updateCopy()
        updateModifierConflictStatus()
        setupGitHubLink()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        updateModifierButtonStates()
        updateFocusWindowPreferenceState()
        updateAccessibilityStatus()
        updateLaunchAtLoginState()
        updateCopy()
        updateModifierConflictStatus()
    }


    @IBAction func modifierClicked(_ sender: NSButton) {
        let moveButtons = [moveAlt, moveCommand, moveControl, moveFn, moveShift]
        let moveModifiers: [Modifiers<Move>] = [.alt, .command, .control, .fn, .shift]
        let resizeButtons = [resizeAlt, resizeCommand, resizeControl, resizeFn, resizeShift]
        let resizeModifiers: [Modifiers<Resize>] = [.alt, .command, .control, .fn, .shift]
        let modifierForButton = Dictionary(
            uniqueKeysWithValues: zip(moveButtons + resizeButtons,
                                      moveModifiers.map { $0.rawValue } + resizeModifiers.map { $0.rawValue } )
        )
        if let modifier = modifierForButton[sender] {
            if moveButtons.contains(sender) {
                let modifiers = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
                let m = Modifiers<Move>(rawValue: modifier)
                let updated = modifiers.toggle(m)
                let resize = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
                guard !modifierBindingsConflict(move: updated, resize: resize) else {
                    sender.state = modifiers.contains(m) ? .on : .off
                    modifierConflictLabel?.isHidden = false
                    modifierConflictLabel?.stringValue = "Move and Resize modifiers must differ."
                    return
                }
                try? updated.save(forKey: .moveModifiers, defaults: Current.defaults())
            } else if resizeButtons.contains(sender) {
                let modifiers = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
                let m = Modifiers<Resize>(rawValue: modifier)
                let updated = modifiers.toggle(m)
                let move = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
                guard !modifierBindingsConflict(move: move, resize: updated) else {
                    sender.state = modifiers.contains(m) ? .on : .off
                    modifierConflictLabel?.isHidden = false
                    modifierConflictLabel?.stringValue = "Move and Resize modifiers must differ."
                    return
                }
                try? updated.save(forKey: .resizeModifiers, defaults: Current.defaults())
            }
            Tracker.shared?.readModifiers()
            updateCopy()
            updateModifierConflictStatus()
        }
    }

    @IBAction func resizeFromNearestCornerClicked(_ sender: Any) {
        let value: NSNumber = {
            var v = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
            v.toggle()
            return NSNumber(booleanLiteral: v)
        }()
        Current.defaults().set(value, forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
        updateCopy()
    }

    @IBAction func hideMenuIconClicked(_ sender: Any) {
        let value: NSNumber = {
            var v = Current.defaults().bool(forKey:
                DefaultsKeys.showMenuIcon.rawValue)
            v.toggle()
            return NSNumber(booleanLiteral: v)
        }()
        Current.defaults().set(value, forKey:
            DefaultsKeys.showMenuIcon.rawValue)
        updateCopy()
        (NSApp.delegate as? AppDelegate)?.updateStatusItemVisibility()
    }
    
    @IBAction func launchAtLoginClicked(_ sender: Any) {
        let requestedState = !isLaunchAtLoginEnabled()
        let result = setLaunchAtLogin(requestedState)
        if case .requiresApproval = result {
            showLoginItemApprovalAlert()
        } else if case .failed = result {
            showLoginItemFailureAlert()
        }
        updateLaunchAtLoginState()
        updateCopy()
    }
    
    @IBAction func requireDragToActivateClicked(_ sender: Any) {
        let value: NSNumber = {
            var v = Current.defaults().bool(forKey: DefaultsKeys.requireDragToActivate.rawValue)
            v.toggle()
            return NSNumber(booleanLiteral: v)
        }()
        Current.defaults().set(value, forKey: DefaultsKeys.requireDragToActivate.rawValue)
        Tracker.shared?.readModifiers()  // Update the tracker with new setting
        updateCopy()
    }

    @IBAction func focusWindowOnManipulationClicked(_ sender: Any) {
        let key = DefaultsKeys.focusWindowOnManipulation.rawValue
        Current.defaults().set(!Current.defaults().bool(forKey: key), forKey: key)
        Tracker.shared?.readModifiers()
        updateFocusWindowPreferenceState()
    }
    
    @IBAction func openSystemSettingsClicked(_ sender: Any) {
        // Ask Accessibility for the native prompt first. On macOS versions
        // where the prompt is unavailable, retain the direct System Settings
        // fallback used by the existing UI.
        if !isTrusted(prompt: true) {
            NSWorkspace.shared.open(Links.securitySystemPreferences)
        }
        updateAccessibilityStatus()
    }
    
    @IBAction func quitClicked(_ sender: Any) {
        NSApp.terminate(nil)
    }
    
    private func setupGitHubLink() {
        githubLink.target = self
        githubLink.action = #selector(githubLinkClicked(_:))
        githubLink.isBordered = false
        githubLink.attributedTitle = NSAttributedString(
            string: "View on GitHub",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            ]
        )
        githubLink.setAccessibilityRole(.link)
        githubLink.setAccessibilityLabel("View HyperWindow on GitHub")
        githubLink.setAccessibilityHelp("Opens the HyperWindow source repository in your browser")
    }
    
    @objc private func githubLinkClicked(_ sender: Any) {
        let url = URL(string: "https://github.com/brettinternet/HyperWindow")!
        NSWorkspace.shared.open(url)
    }
    
}

extension PreferencesController: NSWindowDelegate {
    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateModifierButtonStates()

        resizeFromNearestCorner?.state = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
            ? .on : .off

        showMenuIcon?.state = Current.defaults().bool(forKey: DefaultsKeys.showMenuIcon.rawValue)
            ? .on : .off

        updateLaunchAtLoginState()

        requireDragToActivate?.state = Current.defaults().bool(forKey: DefaultsKeys.requireDragToActivate.rawValue)
            ? .on : .off
        updateFocusWindowPreferenceState()

        updateAccessibilityStatus()
        updateCopy()
        updateModifierConflictStatus()
    }

    func updateModifierButtonStates() {
        let move = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
        let moveButtons = [moveAlt, moveCommand, moveControl, moveFn, moveShift]
        let moveModifiers: [Modifiers<Move>] = [.alt, .command, .control, .fn, .shift]
        for (modifier, button) in zip(moveModifiers, moveButtons) {
            button?.state = move.contains(modifier) ? .on : .off
        }

        let resize = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
        let resizeButtons = [resizeAlt, resizeCommand, resizeControl, resizeFn, resizeShift]
        let resizeModifiers: [Modifiers<Resize>] = [.alt, .command, .control, .fn, .shift]
        for (modifier, button) in zip(resizeModifiers, resizeButtons) {
            button?.state = resize.contains(modifier) ? .on : .off
        }
    }

    private func alignGeneralCheckboxRows() {
        guard let contentView = window?.contentView,
              let moveAlt,
              let resizeFromNearestCorner else { return }

        let shortcutTop = contentView.convert(moveAlt.bounds, from: moveAlt).minY
        let offset = shortcutTop - resizeFromNearestCorner.frame.minY
        for button in [
            resizeFromNearestCorner,
            showMenuIcon,
            launchAtLogin,
            requireDragToActivate,
            focusWindowOnManipulation
        ] {
            button?.frame.origin.y += offset
        }
    }

    private func updateFocusWindowPreferenceState() {
        focusWindowOnManipulation?.state = Current.defaults().bool(
            forKey: DefaultsKeys.focusWindowOnManipulation.rawValue
        ) ? .on : .off
    }

    func updateAccessibilityStatus(trusted trustedState: Bool? = nil) {
        let isEnabled = trustedState ?? isTrusted(prompt: false)
        
        if isEnabled {
            accessibilityStatusLabel?.isHidden = true
            openSystemSettingsButton?.isHidden = true
        } else {
            accessibilityStatusLabel?.isHidden = false
            accessibilityStatusLabel?.stringValue = "⚠️ Accessibility permission is required"
            accessibilityStatusLabel?.textColor = NSColor.systemOrange
            openSystemSettingsButton?.isHidden = false
        }
        resizeSettingsWindow(contentHeight: isEnabled ? 256 : 308)
        alignGeneralCheckboxRows()
    }
    
    func updateCopy() {
        resizeInfoLabel?.stringValue = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
            ? "Resizing will act on the window corner nearest to the cursor."
            : "Resizing will act on the lower right corner of the window."

        versionLabel?.stringValue = appVersion(short: true)
    }

    private func resizeSettingsWindow(contentHeight: CGFloat) {
        guard let window else { return }
        let contentSize = NSSize(width: 390, height: contentHeight)
        guard window.contentView?.frame.size != contentSize else { return }

        let currentFrame = window.frame
        let targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        )
        let origin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetFrame.height
        )
        window.setFrame(
            NSRect(origin: origin, size: targetFrame.size),
            display: window.isVisible
        )
    }

    private func updateModifierConflictStatus() {
        let move = Modifiers<Move>(forKey: .moveModifiers, defaults: Current.defaults())
        let resize = Modifiers<Resize>(forKey: .resizeModifiers, defaults: Current.defaults())
        let hasConflict = modifierBindingsConflict(move: move, resize: resize)
        modifierConflictLabel?.isHidden = !hasConflict
        if hasConflict {
            modifierConflictLabel?.stringValue = "Move and Resize modifiers must differ."
        }
    }

    private func updateLaunchAtLoginState() {
        let enabled = isLaunchAtLoginEnabled()
        Current.defaults().set(enabled, forKey: DefaultsKeys.launchAtLogin.rawValue)
        launchAtLogin?.state = enabled ? .on : .off
    }

    private func showLoginItemApprovalAlert() {
        let alert = NSAlert()
        alert.messageText = "Allow HyperWindow in Login Items"
        alert.informativeText = "Open System Settings → General → Login Items and allow HyperWindow."
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func showLoginItemFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not update Login Items"
        alert.informativeText = "HyperWindow could not change its Login Items setting. Please try again in System Settings → General → Login Items."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
}
