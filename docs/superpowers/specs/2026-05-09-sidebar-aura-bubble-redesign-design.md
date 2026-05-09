# Sidebar Aura + Chat Bubble Visual Redesign

## Problem

Two adjacent visual issues in the browser sidebar:

1. **`SidebarResponseAura`** — the rainbow ring shown while the local AI is
   generating a response toggles a `LinearGradient` start/endpoint with
   `easeInOut(duration: 1.8).repeatForever(autoreverses: true)`. The flip
   reads as mechanical — the gradient's hard endpoints visibly swap rather
   than flow.

2. **`ThreadTurnBubble`** — user and assistant bubbles use a flat 8pt
   rounded rectangle with a hairline `Color.secondary.opacity(0.12)` border
   and no depth cue. They feel plain. Body text (`.callout`, ~13pt) is also
   slightly small.

A third related view, `PendingAssistantBubble` ("Thinking" + spinner),
duplicates the aura's "AI working" signal once the aura motion is
strengthened.

## Goals

- Replace the aura's flip-style animation with continuous, fluid motion that
  cannot bleed onto the transparent sidebar background.
- Give chat bubbles depth through tonal layering (inner top-edge highlight +
  outer drop shadow), no material translucency, no skeuomorphism.
- Bump bubble body text to 14pt.
- Eliminate the redundant pending bubble; the aura is the sole "generating"
  signal.

## Non-goals

- No change to bubble color asymmetry (user = accent, assistant =
  controlBackground stays).
- No change to `pageRow` styling in `ThreadTurnBubble` — it intentionally
  uses `.thinMaterial` to read as a navigation chip, not a chat bubble.
- No change to `BrowserSidebar` layout, scroll behaviour, or threading
  logic.
- No new tests beyond manual visual verification — these are private
  SwiftUI views with no business logic.

## Design

### 1. `SidebarResponseAura`

Located in [Tungsten/Tungsten/Browser/BrowserSplitView.swift:184-252](../../Tungsten/Tungsten/Browser/BrowserSplitView.swift).

**Layering** — outer geometry preserved:

- `RoundedRectangle(cornerRadius: 18, style: .continuous)`
- `.padding(6)`, `.allowsHitTesting(false)`
- No fill (this is the key change — fill would cover the transparent
  `NSVisualEffectView` sidebar backdrop). The current 0.08 fill is dropped.

**Stroke** — replaces the `LinearGradient` stroke and the `isShifted`-driven
endpoint flip:

```swift
RoundedRectangle(cornerRadius: 18, style: .continuous)
    .strokeBorder(
        AngularGradient(
            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
            center: .center,
            angle: .degrees(phase)
        ),
        lineWidth: 1.75
    )
```

The stroke width bumps from 1.5pt to 1.75pt — 1.5pt reads thin once the
gradient is rotating rather than statically saturated.

The palette retains the existing rainbow stops, with the leading red
repeated as the final stop so the angular seam is invisible.

**Motion driver** — `TimelineView(.animation)` wraps the stroke when active:

```swift
TimelineView(.animation) { context in
    let phase = context.date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: 6)
        / 6 * 360
    // … strokeBorder with AngularGradient(angle: .degrees(phase))
}
```

A 6-second full rotation (60°/sec) reads as "active" without being busy.
`TimelineView(.animation)` is frame-paced and stops driving redraws as soon
as the view is removed from the hierarchy, sidestepping the
`repeatForever` restart pitfalls of the current implementation.

**Activation states**:

| `isActive` | `reduceMotion` | Behavior |
|------------|----------------|----------|
| `false`    | any            | `Color.clear` — view body returns nothing visible. No `TimelineView`. |
| `true`     | `true`         | Static `AngularGradient` at angle 0°. No `TimelineView`. |
| `true`     | `false`        | Animated stroke via `TimelineView(.animation)`. |

The whole view fades via `.opacity(isActive ? 1 : 0)` with
`.animation(.smooth(duration: 0.25), value: isActive)` so the ring doesn't
pop on/off.

**Shadow** — keep a single static glow:

```swift
.shadow(color: .cyan.opacity(0.18), radius: 14, y: 0)
```

The current pulsing shadow (driven by `isShifted`) is dropped — motion now
lives entirely in the stroke rotation.

**State removed** — `@State var isShifted`, `updateAnimation()`, all
`onAppear` / `onChange` wiring. The view becomes near-stateless: only the
`@Environment(\.accessibilityReduceMotion)` lookup and the prop.

### 2. `ThreadTurnBubble`

Located in [Tungsten/Tungsten/Browser/BrowserSplitView.swift:649-731](../../Tungsten/Tungsten/Browser/BrowserSplitView.swift).

Only `alignedTextBubble(isUserQuestion:fill:)` changes. `pageRow` is
untouched.

**Typography** — `.font(.callout)` → `.font(.system(size: 14))` for the
bubble `Text`.

**Padding** — `.horizontal 10 / .vertical 7` → `.horizontal 12 / .vertical 8`.
Larger text needs slightly more breathing room.

**Width cap** — `maxWidth: 280` → `maxWidth: 320`.

**Fill opacity** — small bumps to compensate for the removed border:

- User: `Color.accentColor.opacity(0.16)` → `Color.accentColor.opacity(0.18)`
- Assistant: `Color(nsColor: .controlBackgroundColor).opacity(0.92)` →
  `Color(nsColor: .controlBackgroundColor).opacity(0.95)`

**Border** — the current `.strokeBorder(Color.secondary.opacity(0.12),
lineWidth: 1)` overlay is removed entirely.

**Inner highlight** — added as an overlay, masked by the bubble shape:

```swift
.overlay {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        )
        .allowsHitTesting(false)
}
```

Where `highlightOpacity` is `0.10` for user bubbles (over accent tint) and
`0.06` for assistant bubbles (over a near-white control background — too
much white washes out).

**Drop shadow** — must shadow the bubble shape, not the text glyphs.
Replace the `.background(fill, in: RoundedRectangle(...))` shorthand with
an explicit `.background { ... }` closure containing a shadowed shape:

```swift
.background {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(fill)
        .shadow(
            color: .black.opacity(shadowOpacity),
            radius: shadowRadius,
            y: 1
        )
}
```

Per side:

- User: `shadowOpacity = 0.08`, `shadowRadius = 3`
- Assistant: `shadowOpacity = 0.10`, `shadowRadius = 4`

The slightly heavier assistant shadow gives the response a more grounded
feel without resorting to color asymmetry.

The highlight overlay must use `.allowsHitTesting(false)` so the text's
`.textSelection(.enabled)` still receives clicks.

The signature is extended so the caller can pass per-side parameters:

```swift
private func alignedTextBubble(
    isUserQuestion: Bool,
    fill: Color,
    highlightOpacity: Double,
    shadowOpacity: Double,
    shadowRadius: CGFloat
) -> some View
```

Call sites in `body`:

```swift
case .userQuestion:
    alignedTextBubble(
        isUserQuestion: true,
        fill: Color.accentColor.opacity(0.18),
        highlightOpacity: 0.10,
        shadowOpacity: 0.08,
        shadowRadius: 3
    )
case .assistantResponse, .system:
    alignedTextBubble(
        isUserQuestion: false,
        fill: Color(nsColor: .controlBackgroundColor).opacity(0.95),
        highlightOpacity: 0.06,
        shadowOpacity: 0.10,
        shadowRadius: 4
    )
```

### 3. `PendingAssistantBubble` removal

Delete the entire `private struct PendingAssistantBubble`
([BrowserSplitView.swift:787-805](../../Tungsten/Tungsten/Browser/BrowserSplitView.swift)).

Update `ThreadTurnList`
([BrowserSplitView.swift:587-612](../../Tungsten/Tungsten/Browser/BrowserSplitView.swift)):

- Remove the `if isGeneratingResponse { PendingAssistantBubble().id("pending-assistant") }`
  branch from the `LazyVStack`.
- Simplify `scrollTarget`:

  ```swift
  private var scrollTarget: AnyHashable? {
      turns.last.map { AnyHashable($0.id) }
  }
  ```

  The `"pending-assistant"` id is no longer rendered, so the fallback is
  unnecessary. During generation the user's just-sent question is the last
  turn, so scroll-to-bottom still pins correctly.

- The `.onChange(of: isGeneratingResponse)` hook can stay; it now scrolls
  to the latest user turn when generation flips, which is still the desired
  behavior (keeps the input visible if the user scrolled away).

## Risks & mitigations

- **Performance** — `TimelineView(.animation)` redraws the stroke at frame
  rate while active. Stroke is a single shape with an `AngularGradient`,
  GPU-cheap. Only one aura is on screen at a time, only while generating.
- **Dark mode contrast** — assistant bubble shadow at 0.10 opacity on dark
  appearance can disappear; the bubble's brighter fill (`controlBackgroundColor`
  flips to a dark gray) provides separation on its own. Verify in the
  manual test pass; if shadow is invisible in dark mode, that's acceptable —
  the highlight + fill differential carries the depth.
- **`reduceMotion` regression** — current code calls `updateAnimation()` on
  appear, on `isActive` change, and on `reduceMotion` change. New code is
  declarative: branch on `reduceMotion` inside `body`. SwiftUI
  re-evaluates `body` on environment change, so the static-gradient branch
  is taken automatically. No imperative wiring needed.

## Verification (manual)

1. Trigger a local AI response. Aura ring rotates smoothly, no visible
   flip, no flicker. Background visible through the ring's interior (sidebar
   transparency preserved).
2. Toggle System Settings → Accessibility → Display → Reduce Motion.
   Re-trigger. Aura is static, no rotation.
3. Generate a response with a user question above. No "Thinking" bubble
   appears. Scroll position stays pinned to the bottom.
4. Compare bubbles in light and dark mode:
   - User bubble: accent-tinted, top-edge highlight visible, soft drop
     shadow, no border line.
   - Assistant bubble: control-background tinted, slightly heavier shadow.
   - Text reads at 14pt, both sides.
5. Scroll a long thread. Bubbles do not jitter on scroll (no animation
   state tied to scroll).

## Files

- [Tungsten/Tungsten/Browser/BrowserSplitView.swift](../../Tungsten/Tungsten/Browser/BrowserSplitView.swift)
  — sole file modified.
