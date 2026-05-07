# Coming Soon Browser Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the remaining browser shortcut actions from Coming soon to working functionality: New Window, New Incognito Window, Re-open Last Closed Tab, Pin or Unpin Current Tab, Clear Unpinned Tabs, and View History.

**Architecture:** Add per-window browser models, a small command context for shortcuts that need window-level behavior, explicit normal/incognito browser profile state, pinned and recently closed tab state in `BrowserModel`, a persistent non-incognito history store, and CEF request-context support for ephemeral incognito windows. Keep shortcut remapping behavior in the existing catalog/manager model and make the final availability flip only after each backing feature exists.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Objective-C++, CEF `CefRequestContext`, `UserDefaults` JSON persistence, existing shell-based Swift tests, and `xcodebuild`.

---

## File Structure

New files:
- `Tungsten/Tungsten/Browser/BrowserWindowKind.swift`
- `Tungsten/Tungsten/Browser/BrowserWindowRoot.swift`
- `Tungsten/Tungsten/Browser/BrowserCommandContext.swift`
- `Tungsten/Tungsten/Browser/ClosedTab.swift`
- `Tungsten/Tungsten/Browser/HistoryEntry.swift`
- `Tungsten/Tungsten/Browser/HistoryStore.swift`
- `Tungsten/Tungsten/Browser/HistoryView.swift`
- `Tests/HistoryStoreTests.swift`
- `Tests/BrowserTabStateTests.sh`

Modified files:
- `Tungsten/Tungsten/TungstenApp.swift`
- `Tungsten/Tungsten/Browser/BrowserModel.swift`
- `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
- `Tungsten/Tungsten/CEF/TungstenBrowserController.h`
- `Tungsten/Tungsten/CEF/TungstenCEFBridge.mm`
- `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
- `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`
- `Tungsten/Tungsten/Shortcuts/ShortcutEventMonitor.swift`
- `Tests/ShortcutLogicTests.swift`

## Task 1: Lock the Remaining Shortcut Surface with Failing Tests

**Files:**
- Modify: `Tests/ShortcutLogicTests.swift`

- [ ] **Step 1: Replace Coming soon expectations**

Update `testCatalogIncludesAvailableAndComingSoonActions`, `testComingSoonDefaultsDoNotBlockRemapping`, and `testComingSoonActionDoesNotDispatch` so the catalog expectation is that all six remaining actions are `.available` and their default bindings are dispatchable:

- `.newWindow` -> `Command-N`
- `.newIncognitoWindow` -> `Command-Shift-N`
- `.reopenLastClosedTab` -> `Command-Shift-T`
- `.pinOrUnpinCurrentTab` -> `Command-D`
- `.clearUnpinnedTabs` -> `Command-Shift-K`
- `.viewHistory` -> `Command-Y`

Keep the existing checks that omitted Arc concepts such as Little Arc, Spaces, and Split View are absent.

- [ ] **Step 2: Run shortcut tests and verify RED**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: FAIL because the six actions are still marked `.comingSoon`.

## Task 2: Split Browser State Per Window

**Files:**
- Add: `Tungsten/Tungsten/Browser/BrowserWindowKind.swift`
- Add: `Tungsten/Tungsten/Browser/BrowserWindowRoot.swift`
- Add: `Tungsten/Tungsten/Browser/BrowserCommandContext.swift`
- Modify: `Tungsten/Tungsten/TungstenApp.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/ShortcutEventMonitor.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`

- [ ] **Step 1: Add explicit window/profile identity**

Create `BrowserWindowKind`:

```swift
enum BrowserWindowKind: Hashable, Codable {
    case normal
    case incognito

    var sceneID: String {
        switch self {
        case .normal: "browser"
        case .incognito: "incognito-browser"
        }
    }

    var title: String {
        switch self {
        case .normal: "Tungsten"
        case .incognito: "Tungsten Private"
        }
    }
}
```

- [ ] **Step 2: Move `BrowserModel` into a per-window root view**

Create `BrowserWindowRoot` with `@State private var browserModel: BrowserModel`. Initialize the model with a `BrowserWindowKind`, a shared `HistoryStore`, and the shared `ShortcutManager`. Keep `BrowserSplitView` receiving the model through `.environment(browserModel)`.

- [ ] **Step 3: Add a command context for window-level shortcuts**

Create `BrowserCommandContext` as a `@MainActor` value that contains:

```swift
let browserModel: BrowserModel
let openNormalWindow: () -> Void
let openIncognitoWindow: () -> Void
```

Change `ShortcutEventMonitor` to accept a `BrowserCommandContext` instead of only `BrowserModel`.

- [ ] **Step 4: Update app scenes**

In `TungstenApp`, replace the single app-level `BrowserModel` with:

- `@State private var shortcutManager = ShortcutManager()`
- `@State private var historyStore = HistoryStore()`
- one `WindowGroup(id: BrowserWindowKind.normal.sceneID)` that hosts `BrowserWindowRoot(kind: .normal, ...)`
- one `WindowGroup(id: BrowserWindowKind.incognito.sceneID)` that hosts `BrowserWindowRoot(kind: .incognito, ...)`

Use `BrowserWindowRoot` and `@Environment(\.openWindow)` to wire `openNormalWindow` and `openIncognitoWindow` into the command context.

- [ ] **Step 5: Keep existing available shortcuts green**

Run:

```bash
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonWindows build
```

Expected: `BUILD SUCCEEDED`.

## Task 3: Add Ephemeral CEF Contexts for Incognito Windows

**Files:**
- Modify: `Tungsten/Tungsten/CEF/TungstenBrowserController.h`
- Modify: `Tungsten/Tungsten/CEF/TungstenCEFBridge.mm`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`

- [ ] **Step 1: Extend the Objective-C facade**

Add a designated initializer:

```objc
- (instancetype)initWithInitialURL:(NSString *)initialURL incognito:(BOOL)incognito NS_DESIGNATED_INITIALIZER;
```

Keep the existing Swift call site readable by preserving or forwarding `initWithInitialURL:` for normal tabs.

- [ ] **Step 2: Pass an incognito request context to CEF**

In `TungstenCEFBridge.mm`, retain `_isIncognito` and an optional `CefRefPtr<CefRequestContext> _requestContext`. When `_isIncognito` is true, create the context with default `CefRequestContextSettings` and no `cache_path`:

```cpp
CefRequestContextSettings contextSettings;
_requestContext = CefRequestContext::CreateContext(contextSettings, nullptr);
```

Pass `_requestContext` to `CefBrowserHost::CreateBrowser`. For normal tabs, keep passing `nullptr` so they use the existing global persistent CEF cache.

- [ ] **Step 3: Thread profile state through Swift tabs**

Add `kind: BrowserWindowKind` to `BrowserModel` and `isIncognito: Bool` to `BrowserTab`. Construct `TungstenBrowserController(initialURL:incognito:)` from `BrowserTab`.

- [ ] **Step 4: Add a visible private-window marker**

In the sidebar controls, show a compact "Private" label or shield icon only for `.incognito` windows. Task 6 must not record history from incognito tabs.

- [ ] **Step 5: Verify app build**

Run:

```bash
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonIncognito build
```

Expected: `BUILD SUCCEEDED`.

## Task 4: Implement Pinned Tabs and Clear Unpinned Tabs

**Files:**
- Add: `Tests/BrowserTabStateTests.sh`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`

- [ ] **Step 1: Write failing tab-state checks**

Create `Tests/BrowserTabStateTests.sh` that statically verifies `BrowserModel.swift` contains the public model APIs:

- `toggleSelectedTabPin`
- `togglePin`
- `clearUnpinnedTabs`
- `isPinned`

The script should also verify that `BrowserSplitView.swift` contains a pin/unpin context-menu action and a clear-unpinned action path.

Run:

```bash
./Tests/BrowserTabStateTests.sh
```

Expected: FAIL because the APIs and UI wiring do not exist.

- [ ] **Step 2: Add pinned state to tabs**

Add `var isPinned = false` to `BrowserTab`.

- [ ] **Step 3: Add model operations**

Implement:

```swift
func toggleSelectedTabPin()
func togglePin(_ tab: BrowserTab)
func clearUnpinnedTabs()
```

`clearUnpinnedTabs()` must:

- close each removed CEF browser with `closeBrowser()`
- preserve all pinned tabs
- keep the selected tab if it is pinned
- select the first pinned tab if the selected tab was removed
- create a fresh default tab if no pinned tabs remain
- close the find bar when the selected tab is removed

- [ ] **Step 4: Surface pin state in the sidebar**

Update `BrowserTabRow` to show a pin icon for pinned tabs. Add context-menu items:

- `Pin Tab` or `Unpin Tab`
- `Clear Unpinned Tabs`
- existing `Close Tab`

Keep the tab list in stable order; do not reorder pinned tabs in this task.

- [ ] **Step 5: Verify tab-state checks**

Run:

```bash
./Tests/BrowserTabStateTests.sh
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonPinned build
```

Expected: shell checks pass and Xcode reports `BUILD SUCCEEDED`.

## Task 5: Implement Re-open Last Closed Tab

**Files:**
- Add: `Tungsten/Tungsten/Browser/ClosedTab.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Modify: `Tests/BrowserTabStateTests.sh`

- [ ] **Step 1: Extend failing tab-state checks**

Update `Tests/BrowserTabStateTests.sh` to verify:

- `ClosedTab` exists
- `BrowserModel` has `reopenLastClosedTab`
- `BrowserModel.close(_:)` records a closed tab snapshot before removing a non-last normal tab

Run:

```bash
./Tests/BrowserTabStateTests.sh
```

Expected: FAIL because the closed-tab stack does not exist.

- [ ] **Step 2: Add closed-tab snapshots**

Create `ClosedTab`:

```swift
struct ClosedTab: Equatable {
    let urlString: String
    let title: String
    let isPinned: Bool
}
```

Add a private `[ClosedTab]` stack to `BrowserModel`.

- [ ] **Step 3: Record only normal closed tabs**

In `BrowserModel.close(_:)`, when removing a non-last tab from a normal window, push its URL/title/pin snapshot. Do not record incognito closed tabs.

- [ ] **Step 4: Restore the most recent closed tab**

Implement `reopenLastClosedTab()` so it pops the newest snapshot, creates a tab at that URL, restores the title until CEF updates it, restores the pin state, and selects it. If the stack is empty, do nothing and still return control to the caller without a beep or alert.

- [ ] **Step 5: Verify**

Run:

```bash
./Tests/BrowserTabStateTests.sh
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonReopen build
```

Expected: shell checks pass and Xcode reports `BUILD SUCCEEDED`.

## Task 6: Implement History Capture, Persistence, and View

**Files:**
- Add: `Tungsten/Tungsten/Browser/HistoryEntry.swift`
- Add: `Tungsten/Tungsten/Browser/HistoryStore.swift`
- Add: `Tungsten/Tungsten/Browser/HistoryView.swift`
- Add: `Tests/HistoryStoreTests.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
- Modify: `Tungsten/Tungsten/TungstenApp.swift`

- [ ] **Step 1: Write failing history-store tests**

Create `Tests/HistoryStoreTests.swift` with expectations that:

- `recordVisit(urlString:title:visitedAt:)` stores newest entries first
- a repeated URL recorded consecutively updates the existing newest entry instead of duplicating it
- entries are capped at 1000
- `clear()` removes all entries
- malformed URL strings are ignored

Run:

```bash
swiftc Tungsten/Tungsten/Browser/HistoryEntry.swift Tungsten/Tungsten/Browser/HistoryStore.swift Tests/HistoryStoreTests.swift -o /tmp/TungstenHistoryStoreTests && /tmp/TungstenHistoryStoreTests
```

Expected: FAIL before implementation because the files do not exist.

- [ ] **Step 2: Add `HistoryEntry`**

Create a `Codable`, `Identifiable`, `Equatable` value:

```swift
struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var urlString: String
    var title: String
    var visitedAt: Date
}
```

- [ ] **Step 3: Add `HistoryStore`**

Create an `@Observable @MainActor` store backed by JSON in `UserDefaults`. Use a suite/key initializer so tests can isolate persistence:

```swift
init(userDefaults: UserDefaults = .standard, key: String = "HistoryEntries")
```

Persist after every successful record and after `clear()`. Cap entries at 1000.

- [ ] **Step 4: Record history from normal tabs**

Inject the shared `HistoryStore` into each `BrowserModel`. Add a tab URL-change callback so `BrowserControllerObserver.didUpdateURL` can notify the model. Record a visit when:

- the window kind is `.normal`
- the URL has an `http` or `https` scheme
- the URL string is not empty

Use the tab display title when available. When `didUpdateTitle` fires for the newest matching URL, update the entry title.

- [ ] **Step 5: Add `HistoryView`**

Create a SwiftUI view with:

- search field
- newest-first list
- entry title, host, URL, and visited date
- `Open` action that navigates the current tab to the selected URL
- `Clear History` action with a confirmation dialog

Show the view as a sheet from `BrowserSplitView` when `browserModel.isHistoryVisible` is true.

- [ ] **Step 6: Verify history tests and build**

Run:

```bash
swiftc Tungsten/Tungsten/Browser/HistoryEntry.swift Tungsten/Tungsten/Browser/HistoryStore.swift Tests/HistoryStoreTests.swift -o /tmp/TungstenHistoryStoreTests && /tmp/TungstenHistoryStoreTests
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonHistory build
```

Expected: `HistoryStoreTests passed` and `BUILD SUCCEEDED`.

## Task 7: Promote and Dispatch the Six Actions

**Files:**
- Modify: `Tungsten/Tungsten/Shortcuts/Core/ShortcutAction.swift`
- Modify: `Tungsten/Tungsten/Shortcuts/ShortcutDispatcher.swift`
- Modify: `Tests/ShortcutLogicTests.swift`

- [ ] **Step 1: Mark catalog entries available**

Change these catalog entries from `.comingSoon` to `.available`:

- `.newWindow`
- `.newIncognitoWindow`
- `.reopenLastClosedTab`
- `.pinOrUnpinCurrentTab`
- `.clearUnpinnedTabs`
- `.viewHistory`

- [ ] **Step 2: Dispatch through `BrowserCommandContext`**

Update `ShortcutDispatcher.dispatch` so:

- `.newWindow` calls `context.openNormalWindow()`
- `.newIncognitoWindow` calls `context.openIncognitoWindow()`
- `.reopenLastClosedTab` calls `context.browserModel.reopenLastClosedTab()`
- `.pinOrUnpinCurrentTab` calls `context.browserModel.toggleSelectedTabPin()`
- `.clearUnpinnedTabs` calls `context.browserModel.clearUnpinnedTabs()`
- `.viewHistory` calls `context.browserModel.showHistory()`

Keep `guard action.isAvailable` at the top.

- [ ] **Step 3: Update shortcut tests to green**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
```

Expected: `ShortcutLogicTests passed`.

## Task 8: Manual Smoke and Regression Verification

**Files:**
- No source changes unless verification exposes a defect.

- [ ] **Step 1: Run all automated checks**

Run:

```bash
swiftc Tungsten/Tungsten/Shortcuts/Core/*.swift Tests/ShortcutLogicTests.swift -o /tmp/TungstenShortcutLogicTests && /tmp/TungstenShortcutLogicTests
swiftc Tungsten/Tungsten/Browser/HistoryEntry.swift Tungsten/Tungsten/Browser/HistoryStore.swift Tests/HistoryStoreTests.swift -o /tmp/TungstenHistoryStoreTests && /tmp/TungstenHistoryStoreTests
./Tests/BrowserTabStateTests.sh
./Tests/CEFBrowserLifecycleTests.sh
xcodebuild -project Tungsten/Tungsten.xcodeproj -scheme Tungsten -destination 'platform=macOS' -derivedDataPath /tmp/TungstenDerivedDataComingSoonFinal build
```

Expected:

- `ShortcutLogicTests passed`
- `HistoryStoreTests passed`
- `BrowserTabStateTests passed`
- `CEFBrowserLifecycleTests passed`
- `BUILD SUCCEEDED`

- [ ] **Step 2: Launch smoke**

Run the built app from `/tmp/TungstenDerivedDataComingSoonFinal/Build/Products/Debug/Tungsten.app`, then manually verify:

- `Command-N` opens a new normal window
- `Command-Shift-N` opens a private window and does not write visited pages to history
- `Command-D` toggles pin state on the current tab
- `Command-Shift-K` closes unpinned tabs and keeps pinned tabs
- `Command-Shift-T` restores the last closed normal tab
- `Command-Y` opens history
- closing tabs after CEF browser creation does not reintroduce the AppKit unrecognized-selector crash

- [ ] **Step 3: Check crash reports after launch smoke**

Run:

```bash
ls -t ~/Library/Logs/DiagnosticReports/Tungsten*.crash 2>/dev/null | head -5
```

Expected: no new crash report timestamp from the smoke run.

## Self-Review

- The six remaining `ShortcutAvailability.comingSoon` entries have a concrete owner task and final promotion step.
- Window-level shortcuts are routed through a command context because `BrowserModel` alone cannot open SwiftUI windows.
- Incognito uses a separate CEF request context with no cache path, while normal windows keep the existing persistent context.
- History explicitly excludes incognito navigation and persists only normal-window visits.
- Pinned tabs and closed-tab restoration live in `BrowserModel`, matching existing tab ownership.
- Verification includes shortcut unit tests, history unit tests, model/static checks, CEF lifecycle regression checks, Xcode build, and manual CEF smoke.
