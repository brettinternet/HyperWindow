<p align="center">
  <img width="128" src="HyperWindow/Images.xcassets/AppIcon.appiconset/128x128@2x.png" style="padding:0.5rem;">
</p>

<h1 align="center">HyperWindow</h1>

Resize & move apps from anywhere on the window with custom modifiers.

![move or resize from anywhere on a window](./assets/demo.webp)

When the modifiers are active, the cursor position can resize or move the window from anywhere over the app. The cursor follows the window (although not captured by the screen recorder).

![settings window](./assets/screenshot.png)

You may resize from the nearest corner instead of a left-to-right resize. It's also possible to enable activation by the mouse drag action instead of merely hovering over the window, or focus a window whenever HyperWindow moves or resizes it.

If you only need window movement, macOS has a built-in fixed `ctrl+cmd` drag alternative.

```sh
defaults write -g NSWindowShouldDragOnGesture -bool true
```

## Releases

> [!NOTE]  
> I have not elected to sign the app by joining the Apple Developer Program yet. You can create a build yourself, or trust the automated GitHub releases and circumvent Apple's security policy.

The releases are [built and published by a GitHub Action](https://github.com/brettinternet/HyperWindow/actions) and can be installed by bypassing the typical app security on macOS. You're also welcome to build and bundle the app yourself with Xcode. For a signed release, you may install a release from the [original repository](https://github.com/finestructure/Hummingbird) (although some features are missing upstream).

### Build

HyperWindow requires macOS 15.2 or newer. Xcode is required to build the app. Run the release task from `Taskfile.dist.yaml`.

```sh
task build:release # build, ad-hoc sign, and verify the universal app
task copy:release  # build and copy the app to /Applications
task package:release RELEASE_TAG=v0.0.10 # create the DMG and checksum
```

Open the app `build/Build/Products/Release/HyperWindow.app`.

### Publish

Update `MARKETING_VERSION` in the Xcode project, commit it, then push the matching tag:

```sh
git tag v0.0.10
git push origin v0.0.10
```

Tags matching `vMAJOR.MINOR.PATCH` (optionally `-alpha.N`, `-beta.N`, or `-rc.N`) run tests, build the universal app, create a DMG and checksum, and publish a GitHub release. Prerelease tags create prerelease GitHub releases.

### Unsigned Release

Alternatively, to run the unsigned app, clear the quarantine extended attribute at your own risk.

```
xattr -dr com.apple.quarantine /Applications/HyperWindow.app
```

## Known Limitations

This app uses the macOS Accessibility APIs in order to discover windows and update their position and size. Some apps such as Telegram and Stream Deck create windows that don't participate in this mechanism and are invisible to this software.
