# Arc Shortcuts Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a macOS Settings pane where Tungsten users can view and remap the approved Arc-style shortcut catalog, with unsupported actions shown as Coming soon.

**Architecture:** Put shortcut definitions, bindings, persistence, matching, and collision checks in focused Swift files under `Tungsten/Tungsten/Shortcuts`. The app installs one local key event monitor that dispatches available shortcuts through `BrowserModel`, and Settings renders the same shortcut manager so display and runtime behavior share one source of truth.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSEvent`, `UserDefaults`, shell-driven Swift logic tests, Xcode build verification.

---

### File Structure

- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutBinding.swift`
  - Defines `ShortcutModifiers`, `ShortcutBinding`, display formatting, validation, and `NSEvent` conversion.
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
  - Defines shortcut categories, stable action identifiers, availability, and the approved Arc-style catalog.
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutPreferencesStore.swift`
  - Loads and saves user overrides in `UserDefaults`.
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutManager.swift`
  - Owns active bindings, remapping, reset, clear, collision detection, and event-to-action matching.
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutEventMonitor.swift`
  - Installs one app-local keyDown monitor and calls `BrowserModel`.
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`
  - Maps dispatchable shortcut action IDs to `BrowserModel` and `BrowserTab` behavior.
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutSettingsView.swift`
  - Renders grouped shortcut settings rows, record/reset/clear controls, and Coming soon badges.
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
  - Adds selected-tab helpers, recent-tab tracking, pasteboard actions, address focus requests, and sidebar visibility state.
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
  - Binds sidebar visibility and address-input focus request into the UI.
- Modify: `Tungsten/Tungsten/TungstenApp.swift`
  - Creates the shared shortcut manager, adds a Settings scene, removes static `Cmd-T` handling, and installs the shortcut monitor.
- Create: `Tests/ShortcutLogicTests.swift`
  - Runs focused logic tests without adding an Xcode test target.
- Modify: `.gitignore`
  - Removes the `.worktrees/` entry added during setup because the user requested no worktree.

### Task 1: Shortcut Logic Core

**Files:**
- Create: `Tests/ShortcutLogicTests.swift`
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutBinding.swift`
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutPreferencesStore.swift`
- Create: `Tungsten/Tungsten/Shortcuts/Core/ShortcutManager.swift`

- [x] **Step 1: Write the failing shortcut logic tests**

Create `Tests/ShortcutLogicTests.swift` with tests for:

```swift
import AppKit
import Foundation

@main
struct ShortcutLogicTests {
    static func main() throws {
        try testCatalogIncludesAvailableAndComingSoonActions()
        try testOverridesReplaceDefaultsAndResetRestoresDefaults()
        try testClearedBindingLeavesActionUnassigned()
        try testDuplicateActiveBindingsAreDetected()
        try testComingSoonActionDoesNotDispatch()
        try testModifierOrderDoesNotAffectMatching()
        print("ShortcutLogicTests passed")
    }
}
```

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: FAIL because `Tungsten/Tungsten/Shortcuts/Core/*.swift` does not exist.

- [x] **Step 3: Implement shortcut binding and catalog**

Add:

```swift
struct ShortcutBinding: Codable, Equatable, Hashable {
    var key: String
    var modifiers: ShortcutModifiers
}
```

Add default actions for New Tab, Close Tab, Copy URL, Copy URL as Markdown, Focus Address, Toggle Sidebar, Tab 1-9, Recent Tab, Previous/Next Tab, Back, Forward, Reload/Stop, and the approved Coming soon rows.

- [x] **Step 4: Implement persistence and manager logic**

Add `ShortcutPreferencesStore` backed by a `UserDefaults` key named `Tungsten.ShortcutOverrides.v1`. Add `ShortcutManager` methods:

```swift
func activeBindings(for actionID: ShortcutAction.ID) -> [ShortcutBinding]
func setCustomBinding(_ binding: ShortcutBinding, for actionID: ShortcutAction.ID) -> ShortcutAssignmentResult
func clearBinding(for actionID: ShortcutAction.ID)
func resetBinding(for actionID: ShortcutAction.ID)
func conflicts(for binding: ShortcutBinding, excluding actionID: ShortcutAction.ID?) -> [ShortcutAction]
func dispatchableAction(for binding: ShortcutBinding) -> ShortcutAction?
```

- [x] **Step 5: Run tests and verify GREEN**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: PASS with `ShortcutLogicTests passed`.

### Task 2: Browser Model Dispatch Support

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`

- [x] **Step 1: Write a failing compile check for dispatch APIs**

Append tests in `Tests/ShortcutLogicTests.swift` that prove Coming soon actions stay non-dispatchable through the pure core:

```swift
let manager = ShortcutManager(store: ShortcutPreferencesStore(userDefaults: defaults, key: key))
try expect(manager.dispatchableAction(for: ShortcutBinding(key: "f", modifiers: [.command])) == nil)
```

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: FAIL because Coming soon dispatch filtering is not implemented.

- [x] **Step 3: Add BrowserModel shell actions**

Add methods for `closeSelectedTab`, `copySelectedTabURL`, `copySelectedTabURLAsMarkdown`, `focusAddressInput`, `toggleSidebar`, `selectTab(atZeroBasedIndex:)`, `selectPreviousTab`, `selectNextTab`, and `selectRecentTab`. Track `previousSelectedTabID` when `selectedTabID` changes.

- [x] **Step 4: Add dispatch switch**

In `ShortcutDispatcher.dispatch`, switch over action IDs and call the new `BrowserModel` or `BrowserTab` methods. Return `false` for Coming soon actions.

- [x] **Step 5: Run compile-focused tests**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: PASS.

### Task 3: Settings UI and Key Event Routing

**Files:**
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutEventMonitor.swift`
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`
- Create: `Tungsten/Tungsten/Shortcuts/ShortcutSettingsView.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
- Modify: `Tungsten/Tungsten/TungstenApp.swift`

- [x] **Step 1: Implement event monitor**

Add `ShortcutEventMonitor` as a SwiftUI helper view that installs `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`. Convert events to `ShortcutBinding`, ask `ShortcutManager` for the dispatchable action, dispatch through `BrowserModel`, and return `nil` when handled.

- [x] **Step 2: Implement Settings pane**

Add `ShortcutSettingsView` with grouped rows. Each available row has Record, Reset, and Clear. Each Coming soon row shows a disabled badge and no remap controls. Recording uses an `NSViewRepresentable` first-responder capture view and calls `ShortcutManager.setCustomBinding`.

- [x] **Step 3: Wire the main app**

In `TungstenApp.swift`, create shared state:

```swift
@State private var shortcutManager = ShortcutManager()
```

Add `Settings { ShortcutSettingsView(shortcutManager: shortcutManager) }`. Add `ShortcutEventMonitor(shortcutManager: shortcutManager, browserModel: browserModel)` to the main window content. Remove the static `.keyboardShortcut("t")` command.

- [x] **Step 4: Wire focus and sidebar visibility**

In `BrowserSplitView`, bind `BrowserModel.isSidebarVisible` to `NavigationSplitViewVisibility`. In `ChatInput`, observe `BrowserModel.addressFocusRequest` and focus the editor when it changes.

- [x] **Step 5: Build**

Run:

```bash
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataShortcut build
```

Expected: BUILD SUCCEEDED.

### Task 4: Cleanup, Verification, and Commits

**Files:**
- Modify: `.gitignore`
- Modify: all implementation files from prior tasks.

- [x] **Step 1: Remove unused worktree ignore**

Remove the `.worktrees/` ignore entry from `.gitignore`.

- [x] **Step 2: Run final shortcut tests**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: PASS with `ShortcutLogicTests passed`.

- [x] **Step 3: Run final app build**

Run:

```bash
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataShortcut build
```

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Commit implementation**

Run:

```bash
git add .gitignore Tungsten/Tungstens Tests docs/superpowers/plans/2026-05-06-arc-shortcuts-settings.md
git commit -m "Add Arc-style shortcut remapping settings"
```
