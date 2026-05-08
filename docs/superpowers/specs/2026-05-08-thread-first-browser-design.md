# Thread-First Browser Design

## Goal

Tungsten should move from classical browser tabs to chat-like browser threads. A user asks questions or enters URLs in one command input, and Tungsten keeps the resulting question answers and visited pages in a single chronological thread until the user creates a new thread.

The redesign should make the sidebar feel like a conversation history, while the detail pane remains the live browser surface for the active page turn.

## Product Model

A browser window owns a list of threads. Each thread contains ordered turns:

- User question turns.
- Assistant response turns.
- URL/page turns.

The current tab rows become chat bubbles in the selected thread. Text questions produce assistant bubbles in the sidebar. URL submissions produce page turns in the same sidebar and render the selected page in CEF.

Threads are window-scoped. A normal browser window persists its own last 30 threads. Incognito windows keep threads in memory only and never write them to disk.

## Sidebar Experience

The sidebar should have:

- A compact thread switcher and new-thread control at the top.
- A single scrollable timeline for the selected thread.
- Bubbles for user text, assistant responses, and page turns.
- The existing bottom command input, still accepting either questions or URLs.

The timeline should scroll like a chat conversation. Question turns and page turns should share the same scroll history instead of living in separate tab and chat regions.

Page bubbles should show enough metadata to reactivate the page:

- Title when known.
- URL or host.
- Favicon when known.
- Loading state for the active page turn.
- Selected/active state when its page is currently rendered in the detail pane.

## Response Animation

When Tungsten is generating an assistant response, the sidebar should show a polished response-state animation. The target behavior is a restrained, Siri-like rainbow effect without copying Siri assets or adding Apple branding.

The first implementation should use a subtle multicolor animated gradient on the active response area, such as:

- A soft rainbow shimmer around the pending assistant bubble.
- A matching low-opacity accent along the input or sidebar edge.
- Smooth motion that implies activity without pulling attention away from the page.

The animation must respect macOS Reduce Motion. With reduced motion enabled, Tungsten should show a static multicolor accent or a standard progress indicator. The animation must not resize bubbles, shift the timeline, or obscure readable text.

## Detail Pane

Only one URL/page turn in the selected thread should own a live CEF browser controller at a time.

When the active page turn changes:

- The previous live CEF page should be closed or parked.
- The newly selected page turn should receive a live CEF controller.
- If no hibernated browser state is available, Tungsten should reload the stored URL.

Chrome-style tab hibernation is desirable but not required for the first implementation. The first implementation may persist page metadata and reload URLs when older page turns are reactivated.

If the selected thread has no active page turn, the detail pane should show a quiet empty state or the most recent page turn if one exists.

## Input Routing

The command input should classify submitted text as either a navigation target or a question.

URL-like input should:

- Append a page turn to the current thread using the resolved navigation target.
- Activate the page turn.
- Render the URL in CEF.
- Continue recording normal browser history for non-incognito windows.

Question-like input should:

- Append a user question turn.
- Attempt a local AI response.
- Append an assistant response turn when successful.
- Fall back to an AI search page turn when local AI is disabled, unavailable, or fails.

The fallback should use the configured AI search provider so the user still gets a useful result inside the same thread.

## AI Provider Defaults

The default AI behavior should prefer privacy-preserving local inference.

Recommended provider order:

1. Apple on-device local AI through Foundation Models when available.
2. Configured AI search fallback as a page turn.
3. Google/Chromium Gemini Nano only when the user explicitly opts in.

Google local AI should not be enabled by default because it depends on Chromium feature flags, model availability, hardware/storage requirements, and model download behavior. Keeping it opt-in makes the privacy and platform tradeoff explicit.

## Persistence

Normal windows should persist their own last 30 threads. The persisted state should include:

- Thread identifiers.
- Thread titles or derived labels.
- Creation and last-updated dates.
- Ordered turn history.
- Page-turn URL/title/favicon/loading metadata where available.
- The last active page turn for each thread.

The persisted state should not include live CEF controllers or renderer state.

Each normal window should have a stable window-session identifier for thread persistence. If macOS restores a window, Tungsten should restore the matching window-session thread store. If the user opens an additional normal window without restored session identity, Tungsten should create a separate empty window-session store rather than sharing the first window's threads.

On a normal cold launch with no explicit restored window identity, Tungsten should open the most recently active normal window-session store in the first window. This keeps the single-window case simple while preserving separate histories for users who open multiple windows.

When the 31st thread is created in a normal window, Tungsten should evict the oldest thread from that window's persisted set. The selected thread should never be evicted while active.

Incognito windows should keep the same thread UI but store all thread data in memory only.

## Architecture

`BrowserModel` should evolve from tab ownership to thread ownership. The model should expose:

- `threads: [BrowserThread]`
- `selectedThreadID`
- Active page-turn selection for the selected thread.
- Input submission and classification.
- Thread creation, deletion, and selection.
- Persistence loading and saving for normal windows.

`BrowserThread` should contain thread metadata and ordered turns.

`BrowserTurn` should represent question, assistant, and page turns with stable identifiers. Page turns should carry browser metadata but not own CEF directly in persisted state.

A live browser-session owner should manage the one active `TungstenBrowserController` for the selected page turn. This keeps CEF lifecycle separate from thread persistence and makes hibernation/reload policy easier to change later.

## Migration From Tabs

Existing browser tab behavior should map to threads as follows:

- New tab becomes new thread.
- Close current tab becomes close or archive current thread.
- Reopen closed tab can later become reopen closed thread.
- Pinning should either become pinned thread or stay temporarily unsupported until thread pinning is designed.
- Tab selection shortcuts should select threads by index in the current window.
- Back, forward, reload, stop, zoom, and find apply to the active live page turn.

Shortcut labels should be updated from tab language to thread language where the user-facing behavior changes.

## Error Handling

If URL classification produces an invalid target, Tungsten should treat the input as a question instead of dropping it.

If local AI fails, times out, or is unavailable, Tungsten should append a short assistant/system bubble indicating that local AI was unavailable and then append the AI search fallback page turn.

If a reactivated page turn cannot reload, Tungsten should keep the page bubble in the timeline and show the error in the detail pane without deleting history.

If persisted thread data is invalid or from a newer schema, Tungsten should ignore only the invalid thread or turn where possible and keep the rest of the window's thread history.

## Testing

Add focused tests around the non-UI thread logic:

- URL-like input creates and activates a page turn.
- Question-like input creates a user question turn.
- Local AI success appends an assistant response turn.
- Local AI failure appends an AI search page turn.
- Normal windows persist no more than 30 threads.
- Incognito windows never persist threads.
- Reactivating an old page turn creates or reloads the one live page controller.
- Selecting another page turn closes or parks the previous live page controller.
- Invalid persisted thread data does not wipe valid neighboring threads.

UI verification should include:

- Sidebar timeline scroll behavior with mixed question and page turns.
- Response animation during pending answer generation.
- Reduced Motion fallback for the response animation.
- Thread switching and new-thread creation.
- URL reactivation from older page bubbles.

## Out of Scope

The first implementation does not need:

- True Chrome-style memory hibernation.
- Live CEF views embedded inside old sidebar bubbles.
- Cross-window shared thread history.
- Incognito persistence.
- Cloud LLM API integration beyond existing AI search fallback pages.
