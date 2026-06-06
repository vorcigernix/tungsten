# Native macOS redesign — HIG + Liquid Glass

**Date:** 2026-06-06
**Status:** Approved (design); implementing iteratively
**Goal:** Make the working-tree Safari-style tab browser feel genuinely native on macOS 26 by following the Human Interface Guidelines and adopting Liquid Glass correctly.

## Context

The working tree is a Safari-style top-chrome tab browser ([BrowserSplitView.swift](../../../Tungsten/Tungsten/Browser/BrowserSplitView.swift)). It already calls the Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) but fights them:

1. **Opaque navy backing** — `SafariChromeBacking` paints a solid hardcoded `chromeBaseColor` rectangle behind the toolbar. Liquid Glass is meant to float over content and adapt (light↔dark); a solid fill defeats it.
2. **Glass-on-glass** (Apple's #1 "don't") — `.buttonStyle(.glass)` buttons sit inside `glassEffect` pills (`NavigationControls`, `ToolbarActionPill`, `SidebarHistoryPill`).
3. **Hardcoded colors** — `.white.opacity(...)` for nearly all text/icons → no real light mode.
4. **Oversized controls** — 44–48pt pills, 18pt address text, 17–19pt icons vs macOS density (~28pt / 13pt).
5. **Custom 3px accent focus ring**; manual hairline dividers with hardcoded opacities.
6. The chrome is a fully custom `ZStack`, and the page renders full-bleed *under* it — the top ~74–122pt of every web page is occluded.
7. The start page is a Safari clone (mountain gradients, brand-colored favorite tiles, a dead "Extensions" promo).

The `transparencyEnabled` preference is a **dead toggle** (read only by the Settings checkbox), and a well-considered adaptive `opaqueWindowBackgroundColor` (warm taupe in light / warm dark-gray in dark) already exists but is unused.

## Decisions

- **Chrome mechanism: A2 — one custom Liquid-Glass bar** built correctly, hosted in the existing full-size-content system titlebar (transparent titlebar, integrated traffic lights, draggable). Not `NSToolbar` items (a wide search field + custom tab strip map badly onto toolbar items for a CEF content view). The bar uses the same system glass material, so it reads as native while keeping full control of the browser-specific layout.
- **Accent: pure system accent** — follow the user's macOS accent color everywhere (focus rings, selection). No custom Tungsten tint.
- **Light + dark** — full support via semantic/system colors.
- **No centered search box** on the start page — the toolbar field is the search (matches Safari).

## Design

### Chrome architecture
- Keep the layout in spirit: traffic-light gutter → history/sidebar pill → back/forward → centered Smart Search → actions pill. Both `compact` and `separate` tab layouts retained.
- Remove `SafariChromeBacking`'s opaque navy fill. The bar is a single `glassEffect(.regular)` surface over the window backing.
- **Glass-on-glass fix:** each pill/group is the *single* glass surface; inner buttons become `.plain` with `.fill.quaternary` hover / `.fill.tertiary` pressed fills. All groups remain inside the existing `GlassEffectContainer`.

### Page ↔ chrome relationship
- **Inset the CEF view to begin just below the bar** (no more occlusion). The glass bar then shows the window backing behind it (a hint of desktop when translucent; the adaptive solid color when not).

### Design tokens (`Browser/Chrome/ChromeTheme.swift`)
One source of truth for metrics + semantic colors. Replaces all hardcoded values:

| Concern | Before | After |
|---|---|---|
| Text/icons | `.white.opacity(0.86…0.94)` | `.primary` / `.secondary` / `.tertiary` |
| Chrome backing | opaque navy | `glassEffect(.regular)` over window |
| Window backing | (n/a) | material if `transparencyEnabled`, else `opaqueWindowBackgroundColor`; force solid under Reduce Transparency |
| Accent / focus | custom 3px stroke | system focus ring + `Color.accentColor` |
| Separators | white/black opacity hairlines | `Divider()` / `Color(nsColor: .separatorColor)` |
| Control height | 44–48pt | ~28–30pt controls in a ~44pt bar |
| Address text | 18pt | 13pt body (15pt max) |
| Icons | 17–19pt | 13–15pt `.medium` SF Symbols |
| Corners | fixed 18–24pt | concentric (capsules for pills; window-matched radii for cards) |

### Tabs
Favicon + 13pt title (`.primary`/`.secondary`); selected indicator uses `Color.accentColor` at low opacity; hover `.fill.quaternary`; pinned = favicon-only; close = `xmark` `.secondary` with hover fill.

### Window backing (wires the dead pref)
- `transparencyEnabled` on → transparent window, glass over it (vibrant).
- off → window background = `opaqueWindowBackgroundColor`, glass over solid.
- Reduce Transparency (accessibility) → force solid regardless of pref.

### Start page (`Browser/StartPage/StartPageView.swift`)
Remove the Safari clone (`SafariStartBackground` mountains, dead "Extensions" promo, brand-colored cards).
- **Background:** adaptive `windowBackgroundColor` / subtle system material.
- **Favorites:** native tiles using each site's favicon (`FaviconLoader`) on neutral `.fill.quaternary` tiles, monogram fallback. Small default set so first run isn't empty.
- **Frequently Visited:** real data from `HistoryStore` (replaces fake "Suggestions").
- **Private window:** SF Symbol + semantic colors + `.regularMaterial` card.

### Smaller surfaces (polish, not rebuild)
- **History:** swap the custom search `HStack` for `.searchable`.
- **Find bar:** native sizing/semantic colors (already `.regularMaterial`).
- **Settings:** already native `Form(.grouped)`; main change is the transparency wiring above.

### File structure
Split the 988-line `BrowserSplitView.swift` (done after the look is approved, to keep first-view fast):
- `Browser/Chrome/ChromeTheme.swift` — tokens
- `Browser/Chrome/BrowserChrome.swift` — glass bar, controls, tab strip
- `Browser/StartPage/StartPageView.swift` — start page
- `BrowserSplitView.swift` — slim composition (chrome + detail + find bar + history sheet)

## Out of scope (YAGNI)
AI sidebar (separate, disabled-by-default feature) · persisted favorites/bookmarks (follow-up) · CEF internals beyond the content inset · the abandoned thread-first sidebar.

## Acceptance criteria
- Builds and runs.
- Looks correct in **both light and dark**.
- No glass-on-glass; no hardcoded `.white.opacity`/navy in chrome.
- Controls at native sizes; system focus ring.
- Transparency toggle and Reduce Transparency both take effect.
- Web page is no longer occluded by the chrome.

## Verification
Primary verification is visual on the running app (`./scripts/build-debug.sh` → launch), inspected in both appearances, plus a Reduce-Transparency check. Existing logic tests must still pass.
