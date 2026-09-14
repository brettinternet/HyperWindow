import Cocoa
import ServiceManagement


class PreferencesController: NSWindowController {

    var moveAlt: NSButton!
    var moveCommand: NSButton!
    var moveControl: NSButton!
    var moveFn: NSButton!
    var moveShift: NSButton!

    var resizeAlt: NSButton!
    var resizeCommand: NSButton!
    var resizeControl: NSButton!
    var resizeFn: NSButton!
    var resizeShift: NSButton!

    var resizeFromNearestCorner: NSButton!
    var resizeInfoLabel: NSTextField!
    var modifierConflictLabel: NSTextField!

    var showMenuIcon: NSButton!
    var launchAtLogin: NSButton!
    var requireDragToActivate: NSButton!
    var focusWindowOnManipulation: NSButton!

    var versionLabel: NSTextField!
    var accessibilityStatusLabel: NSTextField!
    var openSystemSettingsButton: NSButton!
    var githubLink: NSButton!

    private static let contentWidth: CGFloat = 390

    private var rootStack: NSStackView!

    override func loadWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "HyperWindow Settings"
        window.identifier = NSUserInterfaceItemIdentifier("HyperWindowSettings")
        window.isReleasedWhenClosed = false
        window.isRestorable = true
        window.autorecalculatesKeyViewLoop = true
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("HyperWindowSettings")
        self.window = window
        buildSettingsView()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        updateModifierButtonStates()
        updatePreferenceButtonStates()
        updateAccessibilityStatus()
        updateLaunchAtLoginState()
        updateCopy()
        updateModifierConflictStatus()
        setupGitHubLink()
        resizeSettingsWindow()
    }

    private func buildSettingsView() {
        guard let contentView = window?.contentView else { return }

        moveAlt = modifierButton("⌥")
        moveCommand = modifierButton("⌘")
        moveControl = modifierButton("⌃")
        moveFn = modifierButton("fn")
        moveShift = modifierButton("⇧")
        resizeAlt = modifierButton("⌥")
        resizeCommand = modifierButton("⌘")
        resizeControl = modifierButton("⌃")
        resizeFn = modifierButton("fn")
        resizeShift = modifierButton("⇧")

        resizeFromNearestCorner = checkbox("Resize from corners", action: #selector(resizeFromNearestCornerClicked(_:)))
        resizeFromNearestCorner.toolTip = "Resize windows from the corner nearest to the pointer."
        showMenuIcon = checkbox("Show menu icon", action: #selector(hideMenuIconClicked(_:)))
        showMenuIcon.toolTip = "Show HyperWindow in the menu bar."
        launchAtLogin = checkbox("Launch at login", action: #selector(launchAtLoginClicked(_:)))
        launchAtLogin.toolTip = "Start HyperWindow automatically when you log in."
        requireDragToActivate = checkbox("Require mouse drag", action: #selector(requireDragToActivateClicked(_:)))
        requireDragToActivate.toolTip = "Only move or resize while dragging the mouse."
        focusWindowOnManipulation = checkbox("Focus moved windows", action: #selector(focusWindowOnManipulationClicked(_:)))
        focusWindowOnManipulation.toolTip = "Bring a window into focus when moving or resizing it."

        resizeInfoLabel = secondaryLabel("")
        resizeInfoLabel.maximumNumberOfLines = 2
        modifierConflictLabel = secondaryLabel("Move and Resize modifiers must differ.")
        modifierConflictLabel.textColor = .systemRed
        modifierConflictLabel.isHidden = true

        accessibilityStatusLabel = secondaryLabel("Accessibility permission is required")
        accessibilityStatusLabel.textColor = .systemOrange
        openSystemSettingsButton = NSButton(
            title: "Grant Accessibility Access",
            target: self,
            action: #selector(openSystemSettingsClicked(_:))
        )
        openSystemSettingsButton.bezelStyle = .rounded

        versionLabel = secondaryLabel("")
        versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        githubLink = NSButton(title: "View on GitHub", target: self, action: #selector(githubLinkClicked(_:)))
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitClicked(_:)))
        quitButton.bezelStyle = .rounded

        let shortcutGrid = NSGridView(views: [
            [sectionLabel("Move"), sectionLabel("Resize")],
            [moveAlt, resizeAlt],
            [moveCommand, resizeCommand],
            [moveControl, resizeControl],
            [moveFn, resizeFn],
            [moveShift, resizeShift]
        ])
        shortcutGrid.rowSpacing = 6
        shortcutGrid.columnSpacing = 36
        shortcutGrid.xPlacement = .leading

        let generalStack = verticalStack([
            sectionLabel("General"),
            resizeFromNearestCorner,
            showMenuIcon,
            launchAtLogin,
            requireDragToActivate,
            focusWindowOnManipulation
        ], spacing: 7)

        let settingsStack = NSStackView(views: [shortcutGrid, generalStack])
        settingsStack.orientation = .horizontal
        settingsStack.alignment = .top
        settingsStack.spacing = 44
        settingsStack.setHuggingPriority(.required, for: .horizontal)

        let permissionStack = verticalStack([
            accessibilityStatusLabel,
            openSystemSettingsButton
        ], spacing: 8)

        let footer = NSStackView(views: [versionLabel, githubLink, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.setHuggingPriority(.defaultLow, for: .horizontal)
        footer.views[2].setContentHuggingPriority(.defaultLow, for: .horizontal)

        let separator = NSBox()
        separator.boxType = .separator

        rootStack = verticalStack([
            settingsStack,
            resizeInfoLabel,
            modifierConflictLabel,
            permissionStack,
            separator,
            footer
        ], spacing: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            separator.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            resizeInfoLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            contentView.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])
    }

    private func modifierButton(_ title: String) -> NSButton {
        checkbox(title, action: #selector(modifierClicked(_:)))
    }

    private func checkbox(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.controlSize = .regular
        return button
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return label
    }

    private func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        updateModifierButtonStates()
        updatePreferenceButtonStates()
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
                    resizeSettingsWindow()
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
                    resizeSettingsWindow()
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
        _ = toggleDefaultBool(for: .resizeFromNearestCorner)
        updateCopy()
    }

    @IBAction func hideMenuIconClicked(_ sender: Any) {
        _ = toggleDefaultBool(for: .showMenuIcon)
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
        _ = toggleDefaultBool(for: .requireDragToActivate)
        Tracker.shared?.readModifiers()  // Update the tracker with new setting
        updateCopy()
    }

    @IBAction func focusWindowOnManipulationClicked(_ sender: Any) {
        _ = toggleDefaultBool(for: .focusWindowOnManipulation)
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
    private func updatePreferenceButtonStates() {
        resizeFromNearestCorner?.state = Current.defaults().bool(
            forKey: DefaultsKeys.resizeFromNearestCorner.rawValue
        ) ? .on : .off
        showMenuIcon?.state = Current.defaults().bool(
            forKey: DefaultsKeys.showMenuIcon.rawValue
        ) ? .on : .off
        requireDragToActivate?.state = Current.defaults().bool(
            forKey: DefaultsKeys.requireDragToActivate.rawValue
        ) ? .on : .off
        updateFocusWindowPreferenceState()
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
            accessibilityStatusLabel?.stringValue = "Accessibility permission is required"
            accessibilityStatusLabel?.textColor = NSColor.systemOrange
            openSystemSettingsButton?.isHidden = false
        }
        resizeSettingsWindow()
    }
    
    func updateCopy() {
        resizeInfoLabel?.stringValue = Current.defaults().bool(forKey: DefaultsKeys.resizeFromNearestCorner.rawValue)
            ? "Resizing will act on the window corner nearest to the cursor."
            : "Resizing will act on the lower right corner of the window."

        versionLabel?.stringValue = settingsVersion()
    }

    private func resizeSettingsWindow() {
        guard let window, let contentView = window.contentView, let rootStack else { return }
        contentView.layoutSubtreeIfNeeded()
        let targetContentSize = NSSize(
            width: Self.contentWidth,
            height: rootStack.fittingSize.height + 40
        )
        guard abs(contentView.frame.width - targetContentSize.width) > 0.5
                || abs(contentView.frame.height - targetContentSize.height) > 0.5 else { return }

        let currentFrame = window.frame
        let targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        window.setFrame(
            NSRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - targetFrame.height,
                width: targetFrame.width,
                height: targetFrame.height
            ),
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
        resizeSettingsWindow()
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
