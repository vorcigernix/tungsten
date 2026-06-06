# Streaming Markdown Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream local AI answers into the current thread and render assistant responses as markdown.

**Architecture:** Keep the existing final-response fallback path, but add an optional partial-answer callback to `LocalAIAnswering`. `BrowserModel` creates an empty assistant turn before generation and updates that turn as partial text arrives. Gemma uses LiteRT-LM's C streaming callback; Apple uses `LanguageModelSession.streamResponse`.

**Tech Stack:** Swift 6, SwiftUI, FoundationModels, LiteRT-LM C API via `dlopen`, existing shell/Swift tests.

---

### Task 1: Streaming Model Updates

**Files:**
- Modify: `Tungsten/Tungsten/Browser/AI/LocalAIAnswering.swift`
- Modify: `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`
- Modify: `Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift`
- Modify: `Tungsten/Tungsten/Browser/Threads/BrowserThread.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Test: `Tests/AIResponseCoordinatorTests.swift`
- Test: `Tests/ThreadModelTests.swift`

- [x] Add failing tests for partial answer callbacks and updating an existing assistant turn.
- [x] Implement callback forwarding through provider/coordinator.
- [x] Add `BrowserThread.updateTurnText`.
- [x] Make `BrowserModel` append an empty pending assistant turn and update it during generation.
- [x] Run focused Swift tests.

### Task 2: Native Gemma Streaming

**Files:**
- Modify: `Tungsten/Tungsten/Browser/AI/GemmaLocalAI.swift`
- Test: `Tests/AIResponseCoordinatorTests.swift`
- Test: `Tests/LocalAISettingsTests.sh`

- [x] Add failing tests for Gemma partial streaming callbacks and static use of `litert_lm_conversation_send_message_stream`.
- [x] Resolve the streaming C symbol.
- [x] Bridge LiteRT-LM JSON chunk callbacks into cumulative answer updates.
- [x] Keep the final normalized answer path intact.
- [x] Run focused Swift and shell tests.

### Task 3: Markdown Rendering

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
- Test: `Tests/ThreadBrowserLifecycleTests.sh`

- [x] Add failing static checks for markdown rendering.
- [x] Render assistant/system text with `AttributedString(markdown:)` and fallback plain text.
- [x] Keep user/page rows visually unchanged.
- [x] Run sidebar lifecycle test and full debug build.
