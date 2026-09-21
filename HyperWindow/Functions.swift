import Cocoa
import ServiceManagement


func showAccessibilityAlert() {
    let alert = NSAlert()
    alert.messageText = "Accessibility permissions required"
    alert.informativeText = """
    HyperWindow requires Accessibility permissions in order to be able to move and resize windows for you.

    You can grant Accessibility permission in System Settings → Privacy & Security → Accessibility.

    """
    alert.addButton(withTitle: "Open System Settings")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        NSWorkspace.shared.open(Links.securitySystemPreferences)
    default:
        break
    }
}


func showRestartPrompt() {
    let alert = NSAlert()
    alert.messageText = "Restart required"
    alert.informativeText = """
    HyperWindow has Accessibility permission, but window management could not be activated.

    Restart the app to try again.
    """
    alert.addButton(withTitle: "Restart App")
    alert.addButton(withTitle: "Later")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        restartApp()
    default:
        break
    }
}

func showPermissionRevokedAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Accessibility permissions revoked"
    alert.informativeText = """
    HyperWindow has detected that accessibility permissions were removed.
    
    Window management has been automatically disabled to prevent system instability.
    
    To re-enable window management, please grant accessibility permissions again in System Settings.
    """
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "OK")
    
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        NSWorkspace.shared.open(Links.securitySystemPreferences)
    default:
        break
    }
}


func restartApp() {
    let bundlePath = Bundle.main.bundlePath
    let currentPID = ProcessInfo.processInfo.processIdentifier
    log(.debug, "Attempting to restart app at: \(bundlePath), current PID: \(currentPID)")

    // Keep the script constant and pass all runtime values as arguments. This avoids
    // interpolating a bundle path into shell source and avoids a predictable temp file.
    let script = """
    while kill -0 "$1" 2>/dev/null; do
        sleep 0.1
    done
    exec /usr/bin/open "$2"
    """

    do {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "HyperWindow restart", String(currentPID), bundlePath]
        try task.run()

        log(.debug, "Restart helper launched successfully")

        // Terminate this instance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            log(.debug, "Terminating current instance")
            NSApp.terminate(nil)
        }
    } catch {
        log(.error, "Failed to restart app: \(error)")
        showManualRestartInstructions()
    }
}

private func showManualRestartInstructions() {
    let alert = NSAlert()
    alert.messageText = "Please restart the app manually"
    alert.informativeText = """
    The automatic restart failed. Please manually quit and reopen HyperWindow to activate window management functionality.
    
    The app will now quit.
    """
    alert.addButton(withTitle: "OK")
    alert.runModal()
    NSApp.terminate(nil)
}


func accessibilityTrustOptions(prompt: Bool) -> CFDictionary {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
    let value: CFBoolean = prompt ? kCFBooleanTrue : kCFBooleanFalse
    return [key: value] as CFDictionary
}

func isTrusted(prompt: Bool) -> Bool {
    AXIsProcessTrustedWithOptions(accessibilityTrustOptions(prompt: prompt))
}


func formattedVersion(shortVersion: String, bundleVersion: String, short: Bool = false) -> String {
    short ? shortVersion : "\(shortVersion) (\(bundleVersion))"
}

func appVersion(short: Bool = false) -> String {
    let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    return formattedVersion(shortVersion: shortVersion, bundleVersion: bundleVersion, short: short)
}

func settingsVersion(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
    let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "-"
    guard let commit = infoDictionary["GitCommit"] as? String, !commit.isEmpty else {
        return version
    }
    return "\(version) (\(commit))"
}


// MARK: - Login Item Management

enum LaunchAtLoginUpdateResult {
    case enabled
    case disabled
    case requiresApproval
    case failed
}

func setLaunchAtLogin(_ enabled: Bool) -> LaunchAtLoginUpdateResult {
    let service = SMAppService.mainApp

    if enabled {
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            break
        }
    } else if service.status == .notRegistered {
        return .disabled
    }

    do {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    } catch {
        if enabled && service.status == .requiresApproval {
            return .requiresApproval
        }
        if !enabled && service.status == .notRegistered {
            return .disabled
        }
        log(.error, "Failed to \(enabled ? "enable" : "disable") login item: \(error.localizedDescription)")
        return .failed
    }

    switch service.status {
    case .enabled:
        if enabled {
            return .enabled
        }
        log(.error, "Login item remained enabled after unregistering")
        return .failed
    case .requiresApproval:
        if enabled {
            return .requiresApproval
        }
        log(.error, "Login item still requires approval after unregistering")
        return .failed
    default:
        if !enabled {
            return .disabled
        }
        log(.error, "Login item status did not become enabled after registration: \(service.status.rawValue)")
        return .failed
    }
}

func isLaunchAtLoginEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
}
