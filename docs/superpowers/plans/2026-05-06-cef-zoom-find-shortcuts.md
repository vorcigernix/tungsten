# CEF Zoom and Find Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote CEF-backed Zoom and Find shortcuts from Coming soon to working, remappable actions.

**Architecture:** Keep shortcut availability in the existing catalog, expose the required CEF host calls through `TungstenBrowserController`, and dispatch through `BrowserModel`/`BrowserTab`. The find UI is a small overlay in the browser detail area that owns query entry and forwards search commands to CEF.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Objective-C++, CEF `CefBrowserHost::Zoom`, `Find`, and `StopFinding`.

---

### Task 1: Promote Shortcut Core Actions

**Files:**
- Modify: `Tests/ShortcutLogicTests.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`

- [x] **Step 1: Write failing shortcut tests**

Add expectations that `.zoomIn`, `.zoomOut`, `.resetZoom`, and `.findInPage` are available and dispatchable through `ShortcutManager`.

- [x] **Step 2: Run shortcut tests and verify RED**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: FAIL because Zoom and Find are still Coming soon.

- [x] **Step 3: Make Zoom and Find available**

Change the catalog rows to available and update the dispatcher to call browser model methods for Zoom and Find.

- [x] **Step 4: Run shortcut tests and verify GREEN**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: PASS with `ShortcutLogicTests passed`.

### Task 2: Bridge CEF Zoom and Find

**Files:**
- Modify: `Tungsten/Tungsten/CEF/TungstenBrowserController.h`
- Modify: `Tungsten/Tungsten/CEF/TungstenCEFBridge.mm`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`

- [x] **Step 1: Add CEF controller API**

Expose `zoomIn`, `zoomOut`, `resetZoom`, `find(text:forward:matchCase:findNext:)`, and `stopFinding(clearSelection:)` on `TungstenBrowserController`.

- [x] **Step 2: Implement the CEF host calls**

Call `browser->GetHost()->Zoom(...)`, `Find(...)`, and `StopFinding(...)` when a browser exists.

- [x] **Step 3: Add BrowserModel and BrowserTab methods**

Add model methods to show/focus/close the find bar and tab methods that forward Zoom and Find to the controller.

### Task 3: Add Find Bar UI and Verify

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`

- [x] **Step 1: Render the find bar overlay**

Show a compact trailing overlay above the page when `BrowserModel.isFindBarVisible` is true. Include a text field, previous/next buttons, and a close button.

- [x] **Step 2: Wire find interactions**

Typing updates the current CEF search, Return advances, Previous goes backward, and Close clears CEF selection.

- [x] **Step 3: Run final verification**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataCEFZoomFind build
```

Expected: shortcut tests pass and Xcode reports `BUILD SUCCEEDED`.
