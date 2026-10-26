# Mac App Store feasibility

Last reviewed: 2026-10-26

## Conclusion

HyperWindow can't ship on the Mac App Store without losing its core feature. Distribute it outside the App Store with Developer ID signing and notarization instead.

## Why

Mac App Store apps must be sandboxed [1]. HyperWindow isn't: `HyperWindow/HyperWindow.entitlements` is empty. Turning the sandbox on breaks the core feature:

| Feature | Implementation | Under App Sandbox |
|---|---|---|
| Move/resize other apps' windows | `AXUIElementSetAttributeValue` (`HyperWindow/AXUIElement+ext.swift`) | Blocked. Sandboxed apps can't use Accessibility to control other apps [2][3]. |
| Global mouse/modifier tracking | `CGEvent.tapCreate(... options: .defaultTap)` (`HyperWindow/Tracker.swift`) | Listen-only taps work with Input Monitoring [4]. Active (`.defaultTap`) taps are reported broken [5]. |

Changing the tap to `.listenOnly` is possible. There's no sandbox-safe API for moving or resizing other apps' windows. In a thread about submitting a window manager, Apple DTS said: "I don't have any good news for you here" [6].

Existing App Store window managers (for example, Magnet) are probably grandfathered exceptions, which a new submission can't count on. This is unverified.

## Alternative

Join the Apple Developer Program. Sign with Developer ID, notarize, and keep shipping the DMG through GitHub releases. That removes the `xattr` quarantine workaround and keeps every feature.

## References

1. [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)
2. [rdar://10961566: Sandboxing breaks Accessibility (as a means to control other applications)](http://openradar.appspot.com/10961566)
3. [Stack Overflow: AppSandboxing - Accessibility / AXUIElement](https://stackoverflow.com/questions/36375434/appsandboxing-accessibility-axuielement)
4. [Apple Developer Forums: Accessibility permission in sandboxed app](https://developer.apple.com/forums/thread/707680)
5. [rdar://10961642: Sandboxing breaks active filter event taps](https://openradar.appspot.com/10961642)
6. [Apple Developer Forums: Unable to submit my macOS window-management app](https://developer.apple.com/forums/thread/805556)
