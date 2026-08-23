# Mac App Store readiness

Last reviewed: 2026-08-23

## Conclusion

HyperWindow is not ready for Mac App Store submission because its current Release configuration does not enable App Sandbox. The repository does not establish whether the app's core cross-application Accessibility and global event-monitoring behavior works in a sandboxed, App Store-signed build.

This is a feasibility question, not a proven disqualification. Apple's published guidelines require Mac App Store apps to be appropriately sandboxed, but approval remains review-dependent. The decisive next step is a separate App Store build configuration followed by runtime testing of the complete interaction path.

## Current repository state

### Application shape

- Native Swift/AppKit macOS utility.
- The project contains one application target plus unit/UI test targets; no helper, XPC, privileged-service, or separate login-item target was found.
- Release supports `arm64` and `x86_64`, targets macOS 15.2, and uses bundle identifier `cloud.brett.HyperWindow` (`HyperWindow.xcodeproj/project.pbxproj`).
- `LSUIElement` is enabled, so HyperWindow operates as a menu-bar/agent application rather than a normal Dock application (`HyperWindow/HyperWindow-Info.plist`). This is not inherently disqualifying, but App Review instructions must explain how to find, operate, and quit it.
- Launch at login uses `SMAppService.mainApp` and is controlled by the user (`HyperWindow/Functions.swift`).

### Signing and distribution

- Release enables Hardened Runtime and automatic code signing.
- `HyperWindow/HyperWindow.entitlements` contains an empty dictionary. It does not enable `com.apple.security.app-sandbox`.
- The active release workflow creates an ad-hoc-signed direct-download artifact. It is not an App Store archive.
- The repository contains a Developer ID/notarization workflow template and `developer-id` export options. Developer ID distribution is for direct downloads, not Mac App Store submission.
- No third-party installer, privileged escalation, Sparkle-style updater, custom licensing, downloaded executable code, or executable installation mechanism was found.

### Permission-sensitive behavior

HyperWindow's core feature uses system-wide APIs that must be tested after sandboxing is enabled:

- Requests Accessibility authorization through `AXIsProcessTrustedWithOptions` and directs the user to System Settings (`HyperWindow/Functions.swift`).
- Discovers other applications' windows with Core Graphics and `AXUIElement` (`HyperWindow/AXUIElement+ext.swift`).
- Reads Accessibility attributes and writes other applications' window position and size with `AXUIElementSetAttributeValue` (`HyperWindow/AXUIElement+ext.swift`).
- Installs a global HID event tap for mouse movement, modifier changes, buttons, and drag events (`HyperWindow/Tracker.swift`).
- Posts synthetic mouse events (`HyperWindow/Tracker.swift`).

App Sandbox and Accessibility/TCC authorization are separate controls. The current unsandboxed app working after Accessibility permission is granted does not prove that the same behavior will work in an App Store configuration.

No private framework imports or obvious private API linkage were found. No screen-capture, camera, microphone, location, or contacts API usage was found during this review.

## Required work

### Resolve sandbox feasibility first

Create a separate App Store build configuration that:

1. Enables App Sandbox with `com.apple.security.app-sandbox`.
2. Uses an App Store development/distribution provisioning profile.
3. Adds only entitlements demonstrated to be necessary.
4. Installs under a clean identity so prior TCC grants do not mask permission behavior.
5. Exercises the real application, not only unit tests.

Verify all of the following on the currently shipping macOS release:

- First-launch Accessibility authorization flow.
- Window discovery across multiple applications.
- Moving and resizing standard, full-screen, minimized, and multi-display windows as applicable.
- Global mouse/modifier tracking and synthetic-event behavior.
- Menu-bar discovery, settings access, launch at login, restart, and quit.
- Behavior when Accessibility access is denied, later granted, or revoked while running.

If the core behavior fails under sandboxing, obtain current case-specific guidance from Apple through a Technical Support Incident or App Review communication before redesigning around assumptions. The choices would then be a sandbox-compatible implementation, an Apple-approved entitlement/exception, or continued distribution outside the Mac App Store.

### Prepare the App Store build

After sandbox feasibility is established:

- Register the bundle identifier and create the App Store Connect application record.
- Produce an Xcode archive signed for App Store distribution with the correct provisioning profile.
- Upload through Xcode/App Store Connect and resolve archive validation findings.
- Build with an Apple-accepted Xcode/macOS SDK and test on the currently shipping macOS release.
- Keep the App Store edition self-contained. It must not use an external installer, custom updater, license key, copy protection, downloaded executable code, or root escalation.
- Use the Mac App Store for updates.
- Use StoreKit for subscriptions or feature unlocks. No StoreKit integration is needed for a free app or an app sold for one up-front App Store price.
- Complete export-compliance questions.
- Accept paid-app agreements and provide tax/banking information if the app is monetized.

Notarization and Developer ID signing are direct-distribution concerns; they do not replace the App Store archive and submission path.

### Privacy and review material

- Publish a privacy policy and link it in App Store Connect and from an easily accessible location inside the app.
- Complete App Store Connect's App Privacy disclosures, including any data collected by third-party code.
- Inventory the final archive for privacy-manifest or required-reason API validation findings and add accurate declarations where Apple requires them. No `PrivacyInfo.xcprivacy` file exists currently; this review does not establish that one is required for this macOS target.
- Provide accurate app name, description, category, age rating, icon, screenshots, support URL, contact details, and copyright.
- Ensure screenshots and instructions show the actual menu-bar experience.
- Include detailed review notes covering:
  - where HyperWindow appears after launch;
  - why Accessibility access is needed;
  - how to grant or revoke access;
  - exact steps to move and resize a window;
  - launch-at-login behavior;
  - how to open settings and quit;
  - any non-obvious modifier or mouse interactions.
- Provide App Review full access to every feature and any external resource needed to reproduce the behavior.

## Already favorable

- Hardened Runtime is enabled for Release.
- The app is a self-contained native application with no discovered privileged helper.
- No external update mechanism, custom licensing, payment flow, executable download, or private framework usage was found.
- Launch at login uses the current `SMAppService` API and is user-controlled.
- The app category is configured as Utilities.

These points reduce submission work but do not compensate for the missing sandbox configuration or replace runtime validation.

## References

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), especially sections 2.4.5, 2.5, 3.1, and 5.1.
- [App Sandbox](https://developer.apple.com/app-sandboxing/)
- [Submitting to the App Store](https://developer.apple.com/app-store/submitting/)
- [App Sandbox information — App Store Connect Help](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

Apple's requirements change. Recheck the linked sources and App Store Connect validation output before implementation or submission.
