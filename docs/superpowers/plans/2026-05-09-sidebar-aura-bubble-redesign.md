# Sidebar Aura + Chat Bubble Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sidebar's flip-style rainbow aura with a continuous conic stroke rotation, give chat bubbles depth via tonal layering at 14pt, and remove the now-redundant pending "Thinking" bubble.

**Architecture:** Pure SwiftUI visual changes localized to one file. The aura switches from a `LinearGradient` whose endpoints flip on a `repeatForever` animation to an `AngularGradient` stroke whose angle is driven by `TimelineView(.animation)` — fluid motion, no fill (transparency preserved). Chat bubbles drop their hairline border in favor of an inner top-edge highlight overlay plus a drop shadow attached to the background shape (so glyphs are not blurred).

**Tech Stack:** SwiftUI, AppKit (NSVisualEffectView under the sidebar), Xcode build via existing project. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-05-09-sidebar-aura-bubble-redesign-design.md](../specs/2026-05-09-sidebar-aura-bubble-redesign-design.md)

**No automated tests:** these are private SwiftUI views with no business logic. Verification is a manual visual pass against the spec's checklist, performed once at the end.

---

## File Structure

Single file modified — no new files, no deletions of files.

- **Modify:** `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
  - Lines 184–252: rewrite `SidebarResponseAura` (Task 1)
  - Lines 649–731: update `ThreadTurnBubble.alignedTextBubble` (Task 2)
  - Lines 587–593 + 608–611 + 787–805: remove `PendingAssistantBubble` and its references (Task 3)

Each task lands as one commit.

---

## Task 1: Rewrite `SidebarResponseAura` with conic stroke + TimelineView

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift:184-252`

**Why this task is first:** the aura is the most visible change and is referenced from `BrowserSidebar` at line 179. Changing it first lets you eyeball the motion before touching bubbles.

- [ ] **Step 1: Replace the entire `SidebarResponseAura` struct**

Use the Edit tool. The `old_string` is the current implementation lines 184–252 (the entire `private struct SidebarResponseAura: View { … }` block, ending with the closing `}` of `updateAnimation()`).

Replace with:

```swift
private struct SidebarResponseAura: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    private static let rotationPeriodSeconds: Double = 6
    private static let strokeColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .red
    ]

    var body: some View {
        Group {
            if isActive {
                auraStroke
            } else {
                Color.clear
            }
        }
        .padding(6)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.25), value: isActive)
    }

    @ViewBuilder
    private var auraStroke: some View {
        if reduceMotion {
            strokeShape(angleDegrees: 0)
        } else {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = elapsed
                    .truncatingRemainder(dividingBy: Self.rotationPeriodSeconds)
                let angle = phase / Self.rotationPeriodSeconds * 360
                strokeShape(angleDegrees: angle)
            }
        }
    }

    private func strokeShape(angleDegrees: Double) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: Self.strokeColors,
                    center: .center,
                    angle: .degrees(angleDegrees)
                ),
                lineWidth: 1.75
            )
            .shadow(color: .cyan.opacity(0.18), radius: 14, y: 0)
    }
}
```

This removes:
- `@State private var isShifted` and all its toggling
- `strokeGradient` and `fillGradient` `LinearGradient` computed properties
- `updateAnimation()` and the `onAppear` / `onChange(of: isActive)` / `onChange(of: reduceMotion)` hooks
- The `RoundedRectangle().fill(...)` background that was covering the transparent sidebar

It adds:
- `AngularGradient` stroke rotated by a `TimelineView(.animation)`-driven angle
- A 6-second full rotation (60°/sec)
- A reduceMotion branch that returns a static gradient with no `TimelineView`
- A graceful `.opacity` fade via `.animation(.smooth(duration: 0.25), value: isActive)` on the outer `Group`

- [ ] **Step 2: Build the project**

Run:

```bash
xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  build \
  -quiet
```

Expected: `** BUILD SUCCEEDED **`. If errors appear, fix them before proceeding — common issues are typos in `Self.rotationPeriodSeconds` references or missing imports (none should be needed; `Color`, `RoundedRectangle`, `AngularGradient`, `TimelineView` are all in `SwiftUI` which is already imported at the top of the file).

- [ ] **Step 3: Quick visual sanity check**

You do not need to run the full app for this task in isolation — Task 4 covers the manual verification pass. But if you want a fast smoke test:

```bash
xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  -derivedDataPath build/ \
  build \
  -quiet \
  && open build/Build/Products/Debug/Tungsten.app
```

Trigger a local AI response and confirm the aura ring rotates smoothly with no visible flip. If it looks wrong, do not patch it here — note the issue and address it in Task 4's verification pass after the bubble changes also land.

- [ ] **Step 4: Commit**

```bash
git add Tungsten/Tungsten/Browser/BrowserSplitView.swift
git commit -m "$(cat <<'EOF'
feat(sidebar): conic stroke aura via TimelineView

Replaces the LinearGradient endpoint-flip animation with a continuous
AngularGradient rotation. No fill — preserves the transparent sidebar
backdrop. Reduce-motion branch returns a static gradient.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Tonal-layer chat bubbles at 14pt

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift:649-731`

**Why this task is second:** depends on nothing else. After Task 1 the aura is the right kind of motion; now bubbles get their depth treatment.

- [ ] **Step 1: Update the `var body` switch to pass per-side parameters**

Use the Edit tool. The `old_string` is:

```swift
    var body: some View {
        switch turn.kind {
        case .page:
            pageRow
        case .userQuestion:
            alignedTextBubble(isUserQuestion: true, fill: Color.accentColor.opacity(0.16))
        case .assistantResponse, .system:
            alignedTextBubble(isUserQuestion: false, fill: Color(nsColor: .controlBackgroundColor).opacity(0.92))
        }
    }
```

Replace with:

```swift
    var body: some View {
        switch turn.kind {
        case .page:
            pageRow
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
        }
    }
```

Note the fill opacity bumps: `0.16 → 0.18` (user) and `0.92 → 0.95` (assistant) — small compensation for the removed border.

- [ ] **Step 2: Replace `alignedTextBubble` with the tonal-layer version**

Use the Edit tool. The `old_string` is the entire current `alignedTextBubble` method (the `private func alignedTextBubble(isUserQuestion: Bool, fill: Color) -> some View { … }` block, ending with its closing `}`).

Replace with:

```swift
    private func alignedTextBubble(
        isUserQuestion: Bool,
        fill: Color,
        highlightOpacity: Double,
        shadowOpacity: Double,
        shadowRadius: CGFloat
    ) -> some View {
        HStack {
            if isUserQuestion {
                Spacer(minLength: 36)
            }

            Text(turn.displayTitle)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                        .shadow(
                            color: .black.opacity(shadowOpacity),
                            radius: shadowRadius,
                            y: 1
                        )
                }
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
                .frame(maxWidth: 320, alignment: isUserQuestion ? .trailing : .leading)

            if isUserQuestion == false {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUserQuestion ? .trailing : .leading)
    }
```

Changes vs. the previous version:
- Signature gains `highlightOpacity`, `shadowOpacity`, `shadowRadius`
- `.font(.callout)` → `.font(.system(size: 14))`
- `.padding(.horizontal, 10)` → `12`; `.padding(.vertical, 7)` → `8`
- `.frame(maxWidth: 280, …)` → `320`
- `.background(fill, in: RoundedRectangle(…))` shorthand → explicit `.background { RoundedRectangle(…).fill(fill).shadow(…) }` so the shadow attaches to the shape, not the text glyphs
- `.overlay { RoundedRectangle(…).strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1) }` → `.overlay { RoundedRectangle(…).fill(LinearGradient(top→clear)).allowsHitTesting(false) }` (border replaced with inner top-edge highlight; `allowsHitTesting(false)` keeps text selection working)

- [ ] **Step 3: Build**

```bash
xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  build \
  -quiet
```

Expected: `** BUILD SUCCEEDED **`. If you get an error like `cannot convert value of type 'Double' to expected argument type 'CGFloat'` for `shadowRadius`, the call site values (`3` and `4`) should be inferred as `CGFloat` from context — if not, change them to `CGFloat(3)` / `CGFloat(4)`. Do not silently widen the type.

- [ ] **Step 4: Commit**

```bash
git add Tungsten/Tungsten/Browser/BrowserSplitView.swift
git commit -m "$(cat <<'EOF'
feat(threads): tonal-layer chat bubbles at 14pt

Drops the hairline border, adds a top-edge highlight overlay and a
drop shadow attached to the background shape. Bumps body to 14pt with
a slightly larger 320pt width cap and 12/8 padding.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Remove `PendingAssistantBubble`

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift:587-593` (`scrollTarget`)
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift:608-611` (LazyVStack branch)
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift:787-805` (delete struct)

**Why this task is third:** the aura (Task 1) is now the sole "generating" signal, so the pending bubble is redundant. Doing this last avoids a stretch of time during the migration where neither indicator is present.

- [ ] **Step 1: Simplify `scrollTarget`**

Use the Edit tool. The `old_string` is:

```swift
    private var scrollTarget: AnyHashable? {
        if isGeneratingResponse {
            return AnyHashable("pending-assistant")
        }

        return turns.last.map { AnyHashable($0.id) }
    }
```

Replace with:

```swift
    private var scrollTarget: AnyHashable? {
        turns.last.map { AnyHashable($0.id) }
    }
```

The `"pending-assistant"` id no longer exists in the view tree, so the fallback is unreachable. During generation, the user's just-sent question is `turns.last`, so scroll-to-bottom still pins correctly.

- [ ] **Step 2: Remove the pending branch from the `LazyVStack`**

Use the Edit tool. The `old_string` is:

```swift
                    ForEach(turns) { turn in
                        ThreadTurnBubble(
                            turn: turn,
                            isActivePage: turn.kind == .page && turn.id == activePageTurnID,
                            onActivatePage: onActivatePage
                        )
                        .id(turn.id)
                    }

                    if isGeneratingResponse {
                        PendingAssistantBubble()
                            .id("pending-assistant")
                    }
                }
```

Replace with:

```swift
                    ForEach(turns) { turn in
                        ThreadTurnBubble(
                            turn: turn,
                            isActivePage: turn.kind == .page && turn.id == activePageTurnID,
                            onActivatePage: onActivatePage
                        )
                        .id(turn.id)
                    }
                }
```

The `.onChange(of: isGeneratingResponse)` hook in `ThreadTimeline.body` stays — it now scrolls to the latest user turn when generation flips, which keeps the input visible.

- [ ] **Step 3: Delete the `PendingAssistantBubble` struct**

Use the Edit tool. The `old_string` is the entire struct (lines 787–805):

```swift
private struct PendingAssistantBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Thinking")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

```

Replace with the empty string `""` (delete the struct entirely, including its trailing blank line).

- [ ] **Step 4: Verify no dangling references**

Run:

```bash
grep -n "PendingAssistantBubble\|pending-assistant" Tungsten/Tungsten/Browser/BrowserSplitView.swift
```

Expected: no output (zero matches). If anything is still printed, finish removing it before the build step.

- [ ] **Step 5: Build**

```bash
xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  build \
  -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Tungsten/Tungsten/Browser/BrowserSplitView.swift
git commit -m "$(cat <<'EOF'
refactor(threads): drop redundant pending assistant bubble

The sidebar aura is now the sole "generating" indicator — the
PendingAssistantBubble was a duplicate signal. Simplifies scrollTarget
to always pin to the last turn (during generation that's the user's
question, which is the right anchor).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Manual verification pass

**Files:** none modified (verification only).

This is the only verification step — SwiftUI visual changes have no automated harness in this project. Run all five checks from the spec on a real window.

- [ ] **Step 1: Launch the built app**

```bash
xcodebuild \
  -project Tungsten/Tungsten.xcodeproj \
  -scheme Tungsten \
  -configuration Debug \
  -derivedDataPath build/ \
  build \
  -quiet \
  && open build/Build/Products/Debug/Tungsten.app
```

Expected: app window appears with the sidebar visible.

- [ ] **Step 2: Verify aura motion + transparency**

1. Open or select a thread.
2. Submit a query that triggers the local AI (any question — e.g. "summarize this page").
3. While the response generates, watch the sidebar's outer ring.

Expected:
- The rainbow ring rotates continuously with no visible flip or jump.
- The sidebar interior remains transparent — you can see desktop / window background through the ring's interior, not a tinted fill.
- When generation completes, the ring fades out smoothly (no instant pop).

If the ring pops in/out instead of fading, recheck that the `.animation(.smooth(duration: 0.25), value: isActive)` modifier is on the outer `Group` in `SidebarResponseAura`.

- [ ] **Step 3: Verify reduce-motion branch**

1. Open System Settings → Accessibility → Display → Reduce motion → On.
2. Return to the app and trigger another response.

Expected: the ring is visible but static (no rotation). When done, restore Reduce motion to its previous setting.

- [ ] **Step 4: Verify pending bubble is gone + scroll behavior**

1. With reduce-motion off, in a thread with at least one prior turn, submit a new query.
2. Watch the thread list while the response generates.

Expected:
- No "Thinking" + spinner bubble appears anywhere in the list.
- Scroll position pins to the bottom (the user's just-sent question is visible).
- When the assistant response arrives, the list scrolls smoothly to keep the new turn anchored.

- [ ] **Step 5: Verify bubble depth + 14pt text in light and dark mode**

Light mode first (System Settings → Appearance → Light), then re-do in Dark.

For each mode:
1. Inspect a user-question bubble: accent-tinted background, subtle top-edge highlight visible, soft drop shadow visible (or at least the bubble doesn't read as flat against the sidebar).
2. Inspect an assistant-response bubble: control-background fill, slightly heavier shadow than the user bubble.
3. Confirm body text is noticeably larger than before — 14pt should read as comfortable, not cramped.
4. Click and drag on bubble text to confirm `.textSelection(.enabled)` still works (the highlight overlay must not block hits — it has `.allowsHitTesting(false)`).

If the assistant shadow disappears in dark mode, that's documented as acceptable in the spec — the highlight + fill differential carries the depth there.

- [ ] **Step 6: Final commit (if any tweaks were needed)**

If Steps 2–5 all pass cleanly, no commit is needed. If you had to nudge a value (opacity, shadow radius, color), commit those tweaks now:

```bash
git add Tungsten/Tungsten/Browser/BrowserSplitView.swift
git commit -m "$(cat <<'EOF'
fix(threads): tweak <whichever value> after manual review

<one-line reason>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If everything passed without changes, this task is complete with no commit.

---

## Self-Review

**Spec coverage:**
- Aura: rewrite to AngularGradient stroke + TimelineView, no fill, reduce-motion branch, fade — Task 1 ✅
- Bubble typography 14pt — Task 2 Step 2 ✅
- Bubble fill opacity bumps — Task 2 Step 1 ✅
- Bubble border removal — Task 2 Step 2 ✅
- Inner top-edge highlight overlay — Task 2 Step 2 ✅
- Drop shadow attached to background shape (not text) — Task 2 Step 2 ✅
- Padding + max-width bumps — Task 2 Step 2 ✅
- Per-side highlight/shadow values (0.10/0.06, 0.08/0.10, 3/4) — Task 2 Step 1 ✅
- `pageRow` unchanged — implicit (Task 2 only edits `var body` switch and `alignedTextBubble`) ✅
- `PendingAssistantBubble` deletion — Task 3 Step 3 ✅
- `scrollTarget` simplification — Task 3 Step 1 ✅
- LazyVStack branch removal — Task 3 Step 2 ✅
- Manual verification covering all 5 spec checks — Task 4 ✅

**Placeholder scan:** none. Every code block contains the actual code; commit messages are concrete.

**Type consistency:** `alignedTextBubble` signature in Task 2 Step 1 (call sites) and Task 2 Step 2 (definition) match exactly: `(isUserQuestion: Bool, fill: Color, highlightOpacity: Double, shadowOpacity: Double, shadowRadius: CGFloat) -> some View`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-sidebar-aura-bubble-redesign.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints.

Which approach?
