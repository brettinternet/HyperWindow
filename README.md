<p align="center">
  <img width="128" src="HyperWindow/Images.xcassets/AppIcon.appiconset/128x128@2x.png" style="padding:0.5rem;">
</p>

<h1 align="center">HyperWindow</h1>

Hold your modifiers to move or resize a window from anywhere on it.

![move or resize from anywhere on a window](./assets/demo.gif)

![settings window](./assets/screenshot.png)

## Install

Download the signed and notarized app from [releases](https://github.com/brettinternet/HyperWindow/releases). Requires macOS 15.2+.

Only need move? macOS has a built-in `ctrl+cmd` drag:

```sh
defaults write -g NSWindowShouldDragOnGesture -bool true
```

## Build

Requires Xcode.

```sh
task build:release   # build/Build/Products/Release/HyperWindow.app
task copy:release    # build and copy to /Applications
task package:release RELEASE_TAG=v0.0.10  # DMG and checksum
```

## Limitations

HyperWindow uses the Accessibility APIs, so windows that don't expose themselves there (e.g. Telegram, Stream Deck) can't be moved.
