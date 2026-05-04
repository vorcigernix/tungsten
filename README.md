# Tungsten

Tungsten is a native macOS SwiftUI browser shell backed by the Chromium Embedded Framework.

The app keeps the split-view style of the original Apple sample project, but the sample content has been removed. Browser tabs live in the sidebar, and the toolbar search field works as a combined search/address field.

## CEF Setup

CEF binaries are intentionally not committed to the repository.

```sh
./scripts/setup-cef.sh --arch arm64
```

Then build the macOS app:

```sh
xcodebuild -project Landmarks/Landmarks.xcodeproj -scheme Landmarks -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedData build
```

Debug app builds embed the Release CEF runtime by default. This keeps local browser performance representative while still allowing Swift/AppKit debug builds. To intentionally test CEF's Debug runtime, build with `CEF_RUNTIME_CONFIGURATION=Debug`.

For browser benchmarks such as Speedometer, prefer a Release app build:

```sh
xcodebuild -project Landmarks/Landmarks.xcodeproj -scheme Landmarks -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedData build
```
