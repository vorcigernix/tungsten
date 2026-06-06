# Tungsten

Tungsten is a native macOS SwiftUI browser shell backed by the Chromium Embedded Framework.

Browser tabs live in Safari-style top chrome, and the Smart Search field works as a combined search/address field.

## CEF Setup

CEF binaries are intentionally not committed to the repository.

```sh
./scripts/setup-cef.sh --arch arm64
```

Then build the macOS app:

```sh
./scripts/build-debug.sh
```

Debug app builds embed the Release CEF runtime by default. This keeps local browser performance representative while still allowing Swift/AppKit debug builds. To intentionally test CEF's Debug runtime, build with `CEF_RUNTIME_CONFIGURATION=Debug`.

For browser benchmarks such as Speedometer, prefer a Release app build:

```sh
./scripts/build-release.sh
```

Both scripts pass through extra flags to `xcodebuild` and honor `TUNGSTEN_DERIVED_DATA` to override the derived-data path.
