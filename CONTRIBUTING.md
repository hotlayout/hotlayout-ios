# Contributing

## Setup

Xcode 15 or newer (Swift 5.9). The package has no third-party dependencies.

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

The demo app in `Demo/` has UI tests; see the README for the command. What the tests check is
described in [Tests/README.md](Tests/README.md).

## The contract snapshot

`Tests/HotLayoutTests/Resources/contract/` holds the JSON artifacts the reader implements and the
case tables shared by every HotLayout reader. `Demo/fixtures/` holds the sample screens of the
demo, and `Sources/HotLayout/Resources/` the icon set and the built-in theme the reader ships
with.

These files are a snapshot. The contract is maintained outside this repository, so do not edit
them here: a change to the contract arrives as a new snapshot (`scripts/sync-contract.sh`)
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
