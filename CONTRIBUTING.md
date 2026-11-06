# Contributing

## Setup

Xcode 15 or newer (Swift 5.9). CI runs `swift build` and `swift test` on macOS with Xcode 16. The package has no third-party dependencies.

## Build and test

```sh
swift build
swift test         # rules, shared case tables and off-screen drawing, on macOS
```

The same unit tests run on an iOS simulator, which is the platform the library ships for. Boot
one without its window and test the package scheme:

```sh
xcrun simctl boot <device-id>
xcodebuild test -scheme HotLayout -destination 'platform=iOS Simulator,id=<device-id>'
xcrun simctl shutdown <device-id>
```

The demo app in `Demo/` has UI tests:

```sh
cd Demo
xcodebuild -project HotlayoutDemo.xcodeproj -scheme HotlayoutDemoUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -derivedDataPath build test
```

What the tests check is described in [Tests/README.md](Tests/README.md). The README snippet
is `Tests/HotLayoutAPITests/ReadmeExample.swift` (region `readme`): it is compiled against the
public API only, and `ReadmeExampleTests` fails if the README carries a different text. Change
both together. The other regions of that file are the examples of the documentation site and are
only compiled.

## The demo

The demo (`Demo/`) uses the public API only. Without launch arguments it opens on Obsidian, one of
three showcase apps (Obsidian, Sunny and Orbit; their documents, themes and sample data are in
`Demo/fixtures/apps/`), with a small menu to switch app or to open the fixture list. Their pictures
are loaded from hotlayout.com: the demo resolves the site-relative addresses of the documents itself,
the reader's own rule (https only) is not relaxed. `-app obsidian|sunny|orbit -screen <screenId>
-entry <name> -locale <tag>` opens one app on its own; `-fixtureList YES` lists every fixture of the
contract, and `-fixture <name> -screen <screenId> -locale <tag>` opens one screen of it.

## The contract snapshot

`Tests/HotLayoutTests/Resources/contract/` holds the JSON artifacts the reader implements and the
case tables shared by every HotLayout reader. `Demo/fixtures/` holds the sample screens of the
demo, and `Sources/HotLayout/Resources/` the icon set and the built-in theme the reader ships
with.

The contract is a set of JSON artifacts: `screen-schema.json` (the widgets, their fields and the
rules of drawing in its `x-…` blocks), `theme.json`, `data-contract.json` and `icons.json`, with
the shared case tables in `fixtures/`. Comments in this package name the `x-…` blocks they follow.

These files are a snapshot. The contract is maintained outside this repository, so do not edit
them here: a change to the contract arrives as a new snapshot (`scripts/sync-contract.sh <path-to-a-contract-checkout>`, which copies the artifacts, tables, demo fixtures, icon set and built-in theme)
together with the reader code that implements it. The tests compare every shipped copy with the
artifacts, so a snapshot without a matching change in the reader fails `swift test`.

## Pull requests

- Keep `swift test` green. A change in behaviour comes with a test; a row in a shared case table
  is the best test, because every reader runs it.
- Documents, themes and data come from the network and are untrusted input. A piece of the wrong
  shape is skipped and reported, never a crash; see [docs/security.md](docs/security.md).
- The reader opens nothing itself: URLs, deep links and app actions go to the host's `onAction`.
- The package has no dependencies. Please do not add one without discussing it first.
- Format with `swift-format` using the `.swift-format` file in the root.
