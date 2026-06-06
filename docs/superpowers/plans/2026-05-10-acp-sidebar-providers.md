# ACP Sidebar Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Codex and Claude ACP agents as sidebar assistant providers for general questions and active-page analysis.

**Architecture:** Introduce a provider-neutral sidebar assistant layer above the existing Apple/Gemma local responders. ACP providers use a small newline-delimited JSON-RPC client over stdio, create app-directory sessions, stream `agent_message_chunk` updates into the existing pending assistant bubble, and do not expose filesystem or terminal client capabilities.

**Tech Stack:** Swift, SwiftUI, Foundation `Process`/`Pipe`, JSONSerialization, existing thread-first browser model, existing shell and Swift test style.

---

## File Structure

- Modify `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`: add provider-neutral assistant-provider and ACP provider configuration models.
- Modify `Tungsten/Tungsten/AppPreferences.swift`: persist selected assistant provider plus ACP command settings while preserving legacy `localAIProvider` behavior for CEF bridge compatibility.
- Modify `Tungsten/Tungsten/Settings/GeneralSettingsView.swift`: replace the AI picker with assistant-provider settings and add ACP command fields/status text.
- Modify `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`: route provider-neutral choices to Apple, Gemma, Disabled, or ACP-backed responders.
- Create `Tungsten/Tungsten/Browser/AI/ACP/ACPClient.swift`: implement newline-delimited ACP JSON-RPC parsing, request routing, `initialize`, `session/new`, `session/prompt`, update streaming, and cancellation.
- Create `Tungsten/Tungsten/Browser/AI/ACP/ACPAgentResponder.swift`: adapt ACP client sessions to the existing `LocalAIAnswering` streaming interface.
- Modify `Tungsten/Tungsten/Browser/AI/AIResponseCoordinator.swift`: rename internal terminology from local-only where practical while keeping behavior.
- Modify `Tungsten/Tungsten/Browser/BrowserModel.swift`: select the provider-neutral responder and refresh Gemma only when Gemma is selected.
- Modify `Tungsten/Tungsten/Browser/BrowserSplitView.swift`: hide the Gemma bar when ready and key task refreshes off the provider-neutral selection.
- Modify `Tests/AIResponseCoordinatorTests.swift`: add provider routing and fake ACP streaming tests.
- Modify `Tests/LocalAISettingsTests.sh`: validate new provider settings, ACP configuration text, and hidden ready-bar behavior.
- Modify `Tests/ThreadBrowserLifecycleTests.sh`: update expectations for the conditional Gemma availability bar.

## Task 1: Provider Model And Preferences

**Files:**
- Modify: `Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift`
- Modify: `Tungsten/Tungsten/AppPreferences.swift`
- Test: `Tests/LocalAISettingsTests.sh`

- [ ] **Step 1: Write failing settings expectations**

Add `assistant_provider_file="Tungsten/Tungsten/Browser/AI/LocalAIProvider.swift"` to `Tests/LocalAISettingsTests.sh`, then require these patterns:

```bash
require_pattern "$provider_file" "enum SidebarAssistantProvider" "Sidebar assistant provider model"
require_pattern "$provider_file" "case codexACP" "Codex ACP assistant provider"
require_pattern "$provider_file" "case claudeACP" "Claude ACP assistant provider"
require_pattern "$preferences_file" "assistantProvider" "Assistant provider preference"
require_pattern "$preferences_file" "Tungsten.AssistantProvider.v1" "Assistant provider persistence key"
require_pattern "$preferences_file" "codexACPConfiguration" "Codex ACP configuration preference"
require_pattern "$preferences_file" "claudeACPConfiguration" "Claude ACP configuration preference"
```

- [ ] **Step 2: Run the failing test**

Run: `bash Tests/LocalAISettingsTests.sh`

Expected: FAIL because `SidebarAssistantProvider` and ACP config persistence do not exist.

- [ ] **Step 3: Add provider-neutral models**

Add to `LocalAIProvider.swift`:

```swift
enum SidebarAssistantProvider: String, CaseIterable, Codable, Identifiable {
    case appleLocal
    case gemmaLocal
    case codexACP
    case claudeACP
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleLocal: return "Apple Local AI"
        case .gemmaLocal: return "Gemma LiteRT Local"
        case .codexACP:   return "Codex via ACP"
        case .claudeACP:  return "Claude via ACP"
        case .disabled:   return "Disabled"
        }
    }

    var localAIProvider: LocalAIProvider? {
        switch self {
        case .appleLocal: return .apple
        case .gemmaLocal: return .gemma
        case .disabled:   return .disabled
        case .codexACP, .claudeACP: return nil
        }
    }
}

struct ACPProviderConfiguration: Codable, Equatable, Sendable {
    var command: String
    var arguments: [String]
    var lastError: String?

    static let codexDefault = ACPProviderConfiguration(command: "codex", arguments: ["acp"], lastError: nil)
    static let claudeDefault = ACPProviderConfiguration(command: "claude", arguments: ["acp"], lastError: nil)
}
```

- [ ] **Step 4: Persist assistant provider and ACP config**

Add to `AppPreferences.swift`:

```swift
private static let assistantProviderKey = "Tungsten.AssistantProvider.v1"
private static let codexACPConfigurationKey = "Tungsten.ACP.CodexConfiguration.v1"
private static let claudeACPConfigurationKey = "Tungsten.ACP.ClaudeConfiguration.v1"

var assistantProvider: SidebarAssistantProvider {
    didSet {
        guard oldValue != assistantProvider else { return }
        userDefaults.set(assistantProvider.rawValue, forKey: Self.assistantProviderKey)
        if let localAIProvider = assistantProvider.localAIProvider {
            self.localAIProvider = localAIProvider
        }
    }
}

var codexACPConfiguration: ACPProviderConfiguration {
    didSet {
        guard oldValue != codexACPConfiguration else { return }
        persistACPConfiguration(codexACPConfiguration, key: Self.codexACPConfigurationKey)
    }
}

var claudeACPConfiguration: ACPProviderConfiguration {
    didSet {
        guard oldValue != claudeACPConfiguration else { return }
        persistACPConfiguration(claudeACPConfiguration, key: Self.claudeACPConfigurationKey)
    }
}
```

Initialize `assistantProvider` from the new key, fall back to the stored `localAIProvider`, and keep `localAIProvider` in sync only for `.appleLocal`, `.gemmaLocal`, and `.disabled`.

- [ ] **Step 5: Run settings test**

Run: `bash Tests/LocalAISettingsTests.sh`

Expected: PASS.

## Task 2: ACP Protocol Client With Fake Transport

**Files:**
- Create: `Tungsten/Tungsten/Browser/AI/ACP/ACPClient.swift`
- Test: `Tests/AIResponseCoordinatorTests.swift`

- [ ] **Step 1: Write fake-transport tests**

Add tests that:

```swift
let transport = FakeACPTransport(responses: [
    .response(id: 1, result: ["protocolVersion": 1, "agentCapabilities": [:], "authMethods": []]),
    .response(id: 2, result: ["sessionId": "session-1"]),
    .notification(method: "session/update", params: [
        "sessionId": "session-1",
        "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "Hello"]]
    ]),
    .response(id: 3, result: ["stopReason": "end_turn"])
])
let client = ACPClient(transport: transport, cwd: URL(fileURLWithPath: "/tmp/tungsten-acp"))
```

Verify `initialize`, `session/new`, `session/prompt`, streamed partial text, newline-delimited JSON shape, `clientCapabilities.fs.readTextFile == false`, `clientCapabilities.fs.writeTextFile == false`, `clientCapabilities.terminal == false`, and `mcpServers == []`.

- [ ] **Step 2: Run the failing Swift test**

Run:

```bash
swiftc Tests/AIResponseCoordinatorTests.swift Tungsten/Tungsten/Browser/AI/*.swift Tungsten/Tungsten/Browser/AI/ACP/*.swift Tungsten/Tungsten/Browser/Threads/*.swift -o /tmp/AIResponseCoordinatorTests
```

Expected: FAIL because `ACPClient` and `FakeACPTransport` do not exist.

- [ ] **Step 3: Implement ACP transport abstractions**

Create:

```swift
protocol ACPTransport: Sendable {
    func send(_ message: [String: Any]) async throws
    func receive() async throws -> [String: Any]?
    func close()
}

enum ACPClientError: Error, Equatable {
    case invalidResponse
    case unsupportedProtocol
    case authenticationRequired(String)
    case processUnavailable(String)
}
```

Use `JSONSerialization` for dictionaries because ACP payloads contain flexible protocol objects.

- [ ] **Step 4: Implement request routing**

Implement `ACPClient` as an actor with monotonically increasing integer request IDs. `request(method:params:)` sends JSON-RPC 2.0 dictionaries, reads messages until the matching `id` response, handles `session/update` notifications, and extracts text from `agent_message_chunk` updates.

- [ ] **Step 5: Implement stdio transport**

Add `ACPStdioTransport` using `Process`, `Pipe`, newline-delimited UTF-8 JSON, and stderr capture for diagnostics. It must never write non-JSON to stdin and must reject stdout lines that are not JSON objects.

- [ ] **Step 6: Run fake-transport tests**

Run the focused Swift test.

Expected: PASS.

## Task 3: ACP Responder Adapter

**Files:**
- Create: `Tungsten/Tungsten/Browser/AI/ACP/ACPAgentResponder.swift`
- Modify: `Tungsten/Tungsten/Browser/AI/ProviderBackedLocalAIResponder.swift`
- Test: `Tests/AIResponseCoordinatorTests.swift`

- [ ] **Step 1: Write responder tests**

Add tests that use a fake ACP session client and verify:

```swift
let responder = ACPAgentResponder(
    providerName: "Codex via ACP",
    configuration: ACPProviderConfiguration(command: "codex", arguments: ["acp"], lastError: nil),
    clientFactory: { FakeACPAnswerClient(answer: "Page summary", partials: ["Page", "Page summary"]) }
)
```

The responder returns `.answered("Page summary")`, streams both partials, includes page context in the prompt, and returns `.unavailable("Codex via ACP is unavailable. Check the command in Settings.")` for startup errors.

- [ ] **Step 2: Run failing responder tests**

Expected: FAIL because the adapter does not exist.

- [ ] **Step 3: Implement `ACPAgentResponder`**

Implement `LocalAIAnswering` by building `LocalAIPrompts.prompt(question:pageContext:)`, sending it to an ACP client session, streaming chunks through `onPartialAnswer`, trimming final text, and mapping thrown errors to concise `.unavailable` messages.

- [ ] **Step 4: Route provider choices**

Change `ProviderBackedLocalAIResponder` to accept `@Sendable () -> SidebarAssistantProvider`, plus optional `codexResponder` and `claudeResponder`. Route `.appleLocal`, `.gemmaLocal`, `.disabled`, `.codexACP`, and `.claudeACP`.

- [ ] **Step 5: Preserve local-provider tests**

Update existing provider tests from `.apple`, `.gemma`, `.disabled` to `.appleLocal`, `.gemmaLocal`, `.disabled`.

- [ ] **Step 6: Run AI tests**

Run focused AI tests.

Expected: PASS.

## Task 4: BrowserModel Routing

**Files:**
- Modify: `Tungsten/Tungsten/Browser/BrowserModel.swift`
- Test: `Tests/ThreadModelTests.swift`

- [ ] **Step 1: Add routing expectations**

Extend the existing browser model/local AI override test or add a focused test to verify selected `assistantProvider` is captured before the response task starts.

- [ ] **Step 2: Run failing test**

Expected: FAIL because BrowserModel still reads `localAIProvider`.

- [ ] **Step 3: Wire provider-neutral responder**

In `appendQuestionTurnToSelectedThread`, capture `appPreferences.assistantProvider` and construct:

```swift
ProviderBackedLocalAIResponder(
    provider: { selectedAssistantProvider },
    codexResponder: ACPAgentResponder.codex(configuration: appPreferences.codexACPConfiguration),
    claudeResponder: ACPAgentResponder.claude(configuration: appPreferences.claudeACPConfiguration)
)
```

Keep `localAIOverride` for tests by letting it override the constructed responder.

- [ ] **Step 4: Adjust Gemma refresh checks**

Replace checks for `appPreferences.localAIProvider == .gemma` in browser UI/model refresh paths with `appPreferences.assistantProvider == .gemmaLocal`.

- [ ] **Step 5: Run thread tests**

Run `ThreadModelTests.swift` and `ThreadBrowserLifecycleTests.sh`.

Expected: PASS.

## Task 5: Settings UI And Gemma Ready Bar

**Files:**
- Modify: `Tungsten/Tungsten/Settings/GeneralSettingsView.swift`
- Modify: `Tungsten/Tungsten/Browser/BrowserSplitView.swift`
- Test: `Tests/LocalAISettingsTests.sh`
- Test: `Tests/ThreadBrowserLifecycleTests.sh`

- [ ] **Step 1: Write UI/static expectations**

Require Settings strings for `Codex via ACP`, `Claude via ACP`, `Command`, `Arguments`, and ACP privacy text. Require BrowserSplitView to hide the bar for `.available`:

```bash
require_pattern "$split_view_file" "gemmaLocalAIAvailability.state != \\.available" "Gemma ready bar hidden in sidebar"
```

- [ ] **Step 2: Run failing tests**

Expected: FAIL because the UI has not been updated.

- [ ] **Step 3: Update Settings**

Use `Picker("Assistant", selection: $appPreferences.assistantProvider)` with all `SidebarAssistantProvider` values. Add ACP command/arguments text fields when `.codexACP` or `.claudeACP` is selected. Keep Gemma download/runtime warning and add ready status text in Settings.

- [ ] **Step 4: Hide ready bar**

In `BrowserSplitView`, show `GemmaLocalAIAvailabilityBar` only when:

```swift
appPreferences.assistantProvider == .gemmaLocal &&
browserModel.gemmaLocalAIAvailability.state != .available
```

- [ ] **Step 5: Run UI/static tests**

Run `bash Tests/LocalAISettingsTests.sh` and `bash Tests/ThreadBrowserLifecycleTests.sh`.

Expected: PASS.

## Task 6: Verification And Cleanup

**Files:**
- Modify only files touched by Tasks 1-5.

- [ ] **Step 1: Run focused Swift tests**

Run:

```bash
swiftc Tests/AIResponseCoordinatorTests.swift Tungsten/Tungsten/Browser/AI/*.swift Tungsten/Tungsten/Browser/AI/ACP/*.swift Tungsten/Tungsten/Browser/Threads/*.swift -o /tmp/AIResponseCoordinatorTests
/tmp/AIResponseCoordinatorTests
```

Expected: prints `AIResponseCoordinatorTests passed`.

- [ ] **Step 2: Run shell/static tests**

Run:

```bash
bash Tests/LocalAISettingsTests.sh
bash Tests/ThreadBrowserLifecycleTests.sh
bash Tests/CEFBrowserLifecycleTests.sh
```

Expected: each prints its `passed` line.

- [ ] **Step 3: Build the app**

Run:

```bash
./scripts/build-debug.sh
```

Expected: `Built: /tmp/TungstenDerivedData/Build/Products/Debug/Tungsten.app`.

- [ ] **Step 4: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: Summarize without staging unrelated changes**

Because this work sits on a dirty branch with prior thread-browser and Gemma changes, stage only files intentionally changed for ACP if committing is requested. Do not stage `build/` or unrelated modified files.
