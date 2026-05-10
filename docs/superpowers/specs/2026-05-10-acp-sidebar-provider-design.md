# ACP Sidebar Provider Design

## Summary

Tungsten should support ACP agents as sidebar assistant providers at the same product level as Apple Local AI and Gemma LiteRT Local. The goal is not to embed a coding-agent workspace or recreate Codex inside Tungsten. ACP-backed providers should answer general questions, analyze the active page, and stream Markdown responses into the existing thread-first browser sidebar.

The first version should keep the browser model intact:

- URL turns render pages in CEF.
- Question turns are answered by the selected assistant provider.
- Page context is attached to questions when an active page can provide it.
- Assistant responses stream into the existing pending assistant bubble and render as Markdown.
- Threads persist as browser history, independent of the provider used for a given response.

## Goals

- Add Codex and Claude ACP providers beside Apple Local AI and Gemma LiteRT Local.
- Route sidebar questions to ACP when the selected provider is ACP-backed.
- Pass page content context to ACP providers in the same way as local providers.
- Stream ACP responses into the current thread timeline.
- Keep provider setup and readiness issues in Settings unless user action is needed in the sidebar.
- Hide the Gemma readiness bar when Gemma is ready; keep it visible only for actionable states.

## Non-Goals

- No file-editing UI.
- No terminal UI.
- No project task board or IDE-style agent workspace.
- No per-project workspace picker for first use.
- No client-side implementation of ACP file or terminal request handling in the first version.
- No automatic browser automation by the ACP agent.

## User Experience

Settings gains an assistant provider picker with these logical choices:

- Apple Local AI
- Gemma LiteRT Local
- Codex via ACP
- Claude via ACP
- Disabled

The exact naming can follow existing Settings style, but the product behavior should be clear: the selected provider answers sidebar questions. Apple and Gemma are local providers. Codex and Claude are ACP providers that run through configured external commands.

The browser sidebar remains provider-agnostic. The user types a question, receives a streaming assistant response, and can ask follow-up questions in the same thread. If there is an active page, Tungsten includes a concise page context block in the prompt so the provider can answer questions like "what is this page about?" or "summarize this."

ACP setup belongs in Settings. Each built-in ACP provider shows:

- Display name.
- Command path or command name.
- Optional arguments.
- Readiness status.
- Last error, if startup, authentication, or protocol initialization fails.

The sidebar should show only active response failures or user-actionable setup states. It should not permanently show "Gemma LiteRT Ready" or equivalent ready statuses.

## Provider Model

The existing `LocalAIProvider` concept should not absorb ACP directly as if ACP were another local model runtime. The implementation should introduce a higher-level assistant provider concept that can choose between local and ACP-backed engines.

Recommended shape:

- Keep local provider behavior for Apple, Gemma, and Disabled.
- Add a sidebar assistant provider enum or model that represents all user-selectable answer providers.
- Use a shared answering interface for streaming question responses.
- Let `BrowserModel` depend on the shared answering interface, not on local-only provider details.

This preserves the existing local implementation while making ACP a peer in the UI.

## ACP Runtime

ACP providers run as subprocess-backed JSON-RPC clients. Tungsten should own a small ACP client layer responsible for:

- Starting the configured command.
- Sending `initialize`.
- Creating or reusing a session.
- Sending user prompts via `session/prompt`.
- Receiving `session/update` notifications.
- Converting agent message chunks into sidebar partial response text.
- Cancelling the active prompt when the user submits a new question or switches response context.
- Surfacing startup, authentication, and protocol errors as provider failures.

ACP documentation currently requires `session/new` to include an absolute `cwd`. Since Tungsten is using ACP as a browser assistant rather than a project workspace, the first version should use an app-managed support directory as the session cwd. The cwd should not be presented as a project workspace, and Tungsten should not expose arbitrary project files to the ACP provider by default.

## Prompt Shape

ACP prompts should mirror local AI prompts as closely as possible.

For general questions:

```text
Answer browser sidebar questions concisely. Prefer direct answers, include caveats when needed, and do not invent URLs.

Question:
<user question>
```

For page-aware questions:

```text
Answer browser sidebar questions concisely. Prefer direct answers, include caveats when needed, and do not invent URLs.

Current page:
Title: <title>
URL: <url>
Extracted content:
<bounded page text>

Question:
<user question>
```

The page content should use the same bounded extraction policy as local AI. If no useful page context exists, ACP should answer as a general question instead of failing or falling back to search immediately.

## Data Flow

1. User submits text in the sidebar.
2. Browser model classifies it as URL/search/question using existing thread-first behavior.
3. URL turns create or activate a page turn and render in CEF.
4. Question turns append a user turn and start a provider response task.
5. Browser model captures active page context if available.
6. The selected assistant provider receives the question, optional page context, and streaming callback.
7. Partial response text updates the pending assistant turn.
8. Final response replaces the pending turn text, persists the thread, and clears response state.
9. Failures become assistant/system messages in the current thread with concise remediation text.

## Session Scope

ACP sessions should be scoped by Tungsten browser thread and provider. A thread can maintain conversational continuity with the selected ACP provider without merging unrelated threads. Switching providers starts or selects the appropriate provider session for that thread.

Thread persistence should continue storing the Tungsten turns, not raw ACP protocol logs. ACP session IDs may be persisted only if the provider supports reliable session resume and doing so improves continuity. The first version can recreate sessions from Tungsten thread context when needed.

## Error Handling

Startup errors:

- Show a concise failure in the thread if the user asked a question.
- Store detailed command/protocol error text in Settings.
- Offer no permanent sidebar chrome once the error is resolved.

Authentication errors:

- Surface that the ACP provider requires authentication.
- Prefer provider-native CLI authentication instructions in Settings.
- Do not block Apple/Gemma providers.

Protocol errors:

- Treat invalid JSON-RPC, unsupported protocol versions, and missing required methods as provider unavailable.
- Keep the user-facing message short.

Cancellation:

- Cancelling a question should send ACP cancellation if a session is active.
- Tungsten should still clear its local pending assistant state even if the subprocess does not respond cleanly.

## Privacy And Boundaries

Apple and Gemma remain local-only provider options. ACP providers may use external services through their configured agents, so Settings should make that distinction clear.

Tungsten should send only:

- The user question.
- The active page title, URL, and bounded extracted text when available.
- Prior thread context only if needed for conversational continuity and bounded to a reasonable limit.

Tungsten should not grant first-version ACP providers access to filesystem tools, terminal tools, browser control, cookies, credentials, or arbitrary local files.

## Gemma Readiness UI

The Gemma availability bar should be hidden when `GemmaLocalAIAvailability.state == .available`. It remains visible for:

- Unknown, while checking.
- Downloadable, with the prepare/download action.
- Downloading, with progress.
- Unavailable, with a concise error and refresh action.

Settings should show the ready state and any installed model/runtime details.

## Testing

Unit tests:

- Provider selection maps Apple/Gemma/ACP/Disabled to the correct answering implementation.
- ACP prompt construction includes page context when available.
- ACP prompt construction falls back to general questions when page context is empty.
- Streaming ACP chunks update one pending assistant response.
- ACP errors become stable, concise assistant/system messages.
- Gemma ready availability hides the sidebar status bar.

Protocol tests:

- Fake ACP subprocess or transport verifies initialize, session creation, prompt sending, update parsing, final stop handling, and cancellation.
- Invalid JSON-RPC and unsupported capability responses are handled without hanging.

Lifecycle/static tests:

- Settings exposes ACP provider configuration.
- Existing thread persistence remains capped to the current thread history policy.
- Existing local AI shell tests continue passing.

Manual verification:

- Apple Local AI still answers.
- Gemma LiteRT Local still streams Markdown.
- Codex via ACP answers a general question.
- Claude via ACP answers a page-summary question.
- Switching providers does not corrupt existing thread history.

## Implementation Notes

The implementation should be incremental:

1. Hide Gemma ready sidebar status and move ready details to Settings.
2. Introduce assistant-provider selection without changing response behavior.
3. Add ACP config models and Settings UI.
4. Add a fake-transport-tested ACP client.
5. Add ACP-backed answering implementation.
6. Route selected ACP providers through the existing streaming response path.
7. Add readiness and error reporting.

This keeps the first ACP feature focused on browser assistance while leaving room for richer agent capabilities later if they become a separate, explicit product decision.
