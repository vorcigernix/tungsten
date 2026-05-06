# Arc-Style Shortcuts and Settings Design

## Goal

Tungsten should support an Arc-inspired keyboard workflow for technical users. The app should expose the approved Arc-style shortcut catalog in Settings, let users remap supported actions, and clearly mark unsupported actions as "Coming soon" until the matching browser feature exists.

## Source Behavior

Use Arc's official keyboard shortcut categories as the product reference:

- Everyday Use
- Quick Navigation
- Other

The first implementation targets macOS shortcuts only because Tungsten is a native macOS app.

## Scope

The implementation includes:

- A centralized shortcut action catalog.
- Default macOS bindings for the Arc-style action list.
- User-remappable shortcut overrides persisted in `UserDefaults`.
- Collision detection for active remappable shortcuts.
- A macOS Settings scene with a Shortcuts pane.
- Runtime dispatch for shortcut actions backed by existing Tungsten behavior.
- Disabled "Coming soon" rows for Arc actions that require future browser features.

The implementation does not include the missing product features themselves, such as Incognito, History, Find in Page, webpage zoom, or pinned tabs.

The implementation also intentionally skips Arc actions for Little Arc, Spaces, and Split View. These actions should not appear in Settings in this pass, not even as "Coming soon" rows.

## Shortcut Catalog

Each shortcut action should have:

- Stable identifier.
- User-facing title.
- Category.
- Default key equivalent and modifiers.
- Availability state: available or coming soon.
- Optional coming-soon reason when useful.

Initial available actions:

- New tab.
- Close current tab.
- Copy current tab URL.
- Copy current tab URL as Markdown.
- Change current tab URL / focus the command input.
- Show or hide the sidebar.
- Go directly to tab 1 through tab 9.
- Toggle between recent tabs by tracking the previously selected tab.
- Switch to previous or next tab.
- Go back on tab history.
- Go forward on tab history.
- Reload webpage.
- Stop loading, using the reload shortcut while the selected tab is loading.

Initial coming-soon actions:

- New window.
- New incognito window.
- Re-open last closed tab.
- Pin or unpin current tab.
- Clear unpinned tabs.
- View History.
- Zoom in webpage.
- Zoom out webpage.
- Reset webpage zoom.
- Find in webpage.

## Runtime Architecture

Add a shortcut manager that owns the catalog, user overrides, collision checks, and dispatch decisions. App-level key handling should route key events through this manager so remapped shortcuts work without scattering bindings across SwiftUI views.

The shortcut manager should call into `BrowserModel` for browser-shell actions and into the selected `BrowserTab` for page navigation actions. Unsupported actions should never dispatch; they remain visible in Settings only.

SwiftUI menu commands may still be used for discoverability, but runtime shortcut handling should come from the shared shortcut manager so Settings and execution use the same source of truth.

## Settings UI

Add a macOS `Settings` scene with a Shortcuts pane.

The Shortcuts pane should:

- Group shortcuts by Arc category.
- Show the action title.
- Show the current shortcut or "Unassigned".
- Show "Coming soon" for unsupported actions.
- Let users record a new shortcut for available actions.
- Let users reset an action to its default binding.
- Prevent duplicate active bindings by reporting which action already uses the shortcut.
- Let users clear an available action's custom binding, leaving it unassigned until reset.

The pane should be dense and utility-focused. It should feel like a technical settings surface, not a marketing page.

## Persistence

Store user overrides in `UserDefaults` using stable action identifiers. Defaults remain in code so missing or invalid saved values can fall back safely.

Persist only user changes, not the entire catalog. That keeps future catalog migrations small and lets new actions inherit their default bindings automatically.

## Error Handling

Invalid saved shortcut data should be ignored and replaced by the default binding for that action. Duplicate saved bindings should prefer defaults and surface the conflict in Settings instead of silently dispatching ambiguous shortcuts.

Shortcut recording should reject inputs that cannot form a usable keyboard shortcut, such as modifier-only input.

## Testing

Add focused tests around the non-UI shortcut logic:

- Default bindings load for available and coming-soon actions.
- User overrides replace defaults.
- Reset returns an action to its default binding.
- Duplicate active bindings are detected.
- Coming-soon actions are not dispatchable.
- Key-equivalent matching handles modifier order consistently.

Settings UI and app-level key routing should be verified with a build and, where feasible, light manual smoke testing.
