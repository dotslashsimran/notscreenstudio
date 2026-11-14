# notscreenstudio

A free, native macOS screen recorder in the style of Screen Studio. One click to record from the menu bar, then edit with auto-zoom, a smooth cursor, backgrounds and a camera bubble, and export to MP4. Everything stays on your Mac: no network, no telemetry, no accounts.

See [PLAN.md](PLAN.md) for the design and [AGENTS.md](AGENTS.md) for contributor rules.

## Requirements

macOS 15 and Swift 6.1 (Command Line Tools are enough, Xcode is not needed).

## Build and test

```sh
swift build
swift test
```

Tests use Swift Testing, because XCTest is not available with Command Line Tools only.

## Bundle the app

```sh
scripts/bundle.sh
open build/NotScreenStudio.app
```

macOS only grants screen recording, camera and microphone permissions (TCC) to a real app bundle with a bundle identifier and an Info.plist that explains each permission. A bare binary from `.build/` cannot hold those permissions reliably. The script wraps the release binary into `build/NotScreenStudio.app` and signs it ad hoc with `codesign -s -`, so the app has a stable bundle identifier. Ad-hoc signing gives every rebuild a new code hash, so macOS may treat a rebuilt app as a new app and you may need to grant screen recording, camera and microphone permission again after each rebuild.
