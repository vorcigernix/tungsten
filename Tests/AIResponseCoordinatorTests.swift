import Foundation

@main
struct AIResponseCoordinatorTests {
    static func main() async throws {
        try await testLocalSuccessReturnsAssistantAnswer()
        try await testLocalStreamingPublishesPartialAnswers()
        try await testPageContextIsPassedToLocalAI()
        try await testUnavailableLocalAIReturnsFallbackPage()
        try await testFallbackDoesNotSendPageContextToWebSearch()
        try await testFallbackUsesCurrentSearchEngine()
        try await testSimpleArithmeticBypassesLocalAI()
        try await testPageMissAnswerRetriesAsGeneralQuestion()
        try await testProviderBackedResponderUsesAppleResponder()
        try await testProviderBackedResponderUsesGemmaResponder()
        try await testProviderBackedResponderUsesCodexACPResponder()
        try await testProviderBackedResponderReportsDisabledProvider()
        try await testGemmaManagerWarnsBeforeLiteRTDownload()
        try await testGemmaManagerOffersRuntimeRepairWhenModelIsInstalled()
        try await testGemmaManagerInstallsLiteRTLibraryWithoutRedownloadingModel()
        try await testGemmaManagerExtractsLiteRTLibraryFromWheel()
        try await testGemmaResponderReportsMissingRuntimeBeforeDownload()
        try await testGemmaResponderTrimsLiteRTOutput()
        try await testGemmaResponderStreamsPartialAnswers()
        try await testGemmaResponderUsesNativeRuntimeWithSystemInstructionsAndUserPrompt()
        try await testGemmaResponderStripsLiteRTPromptEchoAndBenchmarkInfo()
        try await testGemmaResponderRejectsRuntimeShellTranscript()
        try await testACPClientCreatesSessionWithBrowserAssistantCapabilities()
        try await testACPClientStreamsAgentMessageChunks()
        try await testACPAgentResponderStreamsPageAwareAnswer()
        try await testACPAgentResponderReusesSessionClient()
        try await testACPAgentResponderReportsStartupFailure()
        try testCodexACPDefaultsUseAdapterCommand()
        try testCodexACPLaunchConfigurationDisablesInheritedMCPServers()
        try testACPTransportFindsZedExternalAgent()
        try testGemmaRuntimeDefaultsUseLiteRTLibraryWheel()
        try testPagePromptFallsBackToGeneralKnowledge()
        try testPageContextOnlyAttachesForPageAwareQuestions()
        try testPageContextPrefersSelectedTextAndCapsContent()
        print("AIResponseCoordinatorTests passed")
    }

    static func testLocalSuccessReturnsAssistantAnswer() async throws {
        let coordinator = AIResponseCoordinator(localAI: StubLocalAI(result: .answered("Local answer")))

        let result = await coordinator.response(for: "What is Tungsten?", searchEngine: .duckDuckGo)

        try expect(result == .assistant("Local answer"))
    }

    static func testLocalStreamingPublishesPartialAnswers() async throws {
        let localAI = StreamingLocalAI(result: .answered("Full answer"), partials: ["Full", "Full answer"])
        let coordinator = AIResponseCoordinator(localAI: localAI)
        final class Capture: @unchecked Sendable {
            var partials = [String]()
        }
        let capture = Capture()

        let result = await coordinator.response(
            for: "What is Tungsten?",
            searchEngine: .duckDuckGo,
            onPartialAnswer: { partial in
                capture.partials.append(partial)
            }
        )

        try expect(result == .assistant("Full answer"))
        try expect(capture.partials == ["Full", "Full answer"])
    }

    static func testPageContextIsPassedToLocalAI() async throws {
        let localAI = RecordingLocalAI(result: .answered("Page answer"))
        let coordinator = AIResponseCoordinator(localAI: localAI)
        let pageContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com/docs",
            selectedText: "Selected text",
            bodyText: "Full page text"
        )

        let result = await coordinator.response(
            for: "What is on this page?",
            searchEngine: .duckDuckGo,
            pageContext: pageContext
        )

        try expect(result == .assistant("Page answer"))
        try expect(localAI.capturedQuestion == "What is on this page?")
        try expect(localAI.capturedPageContext == pageContext)
    }

    static func testUnavailableLocalAIReturnsFallbackPage() async throws {
        let reason = "Local AI is unavailable."
        let coordinator = AIResponseCoordinator(localAI: StubLocalAI(result: .unavailable(reason)))

        let result = await coordinator.response(for: "What is Tungsten?", searchEngine: .duckDuckGo)

        try expect(result == .fallbackPage(
            systemMessage: reason,
            urlString: "https://duckduckgo.com/?q=What%20is%20Tungsten?"
        ))
    }

    static func testFallbackDoesNotSendPageContextToWebSearch() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable("Local AI is unavailable."))
        )
        let pageContext = PageContentContext(
            title: "Private doc",
            urlString: "https://example.com/private",
            selectedText: nil,
            bodyText: "do not upload this page text"
        )

        let result = await coordinator.response(
            for: "Summarize this",
            searchEngine: .duckDuckGo,
            pageContext: pageContext
        )

        try expect(result == .fallbackPage(
            systemMessage: "Local AI is unavailable. Page content was kept local and was not sent to web search.",
            urlString: "https://duckduckgo.com/?q=Summarize%20this"
        ))
    }

    static func testFallbackUsesCurrentSearchEngine() async throws {
        let coordinator = AIResponseCoordinator(
            localAI: StubLocalAI(result: .unavailable("Local AI is unavailable."))
        )

        let googleResult = await coordinator.response(for: "What is Tungsten?", searchEngine: .google)
        let duckDuckGoResult = await coordinator.response(for: "What is Tungsten?", searchEngine: .duckDuckGo)

        try expect(googleResult == .fallbackPage(
            systemMessage: "Local AI is unavailable.",
            urlString: "https://www.google.com/search?q=What%20is%20Tungsten?"
        ))
        try expect(duckDuckGoResult == .fallbackPage(
            systemMessage: "Local AI is unavailable.",
            urlString: "https://duckduckgo.com/?q=What%20is%20Tungsten?"
        ))
    }

    static func testSimpleArithmeticBypassesLocalAI() async throws {
        let localAI = RecordingLocalAI(result: .answered("model answer"))
        let coordinator = AIResponseCoordinator(localAI: localAI)

        let result = await coordinator.response(for: "25 times 165.3", searchEngine: .duckDuckGo)

        try expect(result == .assistant("4132.5"))
        try expect(localAI.capturedQuestion == nil)
    }

    static func testPageMissAnswerRetriesAsGeneralQuestion() async throws {
        let localAI = RecordingSequenceLocalAI(results: [
            .answered("The page context does not contain enough information to answer."),
            .answered("Alexander Fleming discovered penicillin.")
        ])
        let coordinator = AIResponseCoordinator(localAI: localAI)
        let pageContext = PageContentContext(
            title: "Unrelated page",
            urlString: "https://example.com",
            selectedText: nil,
            bodyText: "A page about browser release notes."
        )

        let result = await coordinator.response(
            for: "Who discovered penicillin?",
            searchEngine: .duckDuckGo,
            pageContext: pageContext
        )

        try expect(result == .assistant("Alexander Fleming discovered penicillin."))
        try expect(localAI.capturedPageContexts.count == 2)
        try expect(localAI.capturedPageContexts[0] == pageContext)
        try expect(localAI.capturedPageContexts[1] == nil)
    }

    static func testProviderBackedResponderUsesAppleResponder() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .appleLocal },
            appleResponder: StubLocalAI(result: .answered("Stub answer"))
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .answered("Stub answer"))
    }

    static func testProviderBackedResponderUsesGemmaResponder() async throws {
        let appleResponder = RecordingLocalAI(result: .answered("Apple sidebar answer"))
        let gemmaResponder = RecordingLocalAI(result: .answered("Gemma sidebar answer"))
        let pageContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com/docs",
            selectedText: "Selected",
            bodyText: "Body"
        )
        let responder = ProviderBackedLocalAIResponder(
            provider: { .gemmaLocal },
            appleResponder: appleResponder,
            gemmaResponder: gemmaResponder
        )

        let result = await responder.answer("What is Tungsten?", pageContext: pageContext)

        try expect(result == .answered("Gemma sidebar answer"))
        try expect(appleResponder.capturedQuestion == nil)
        try expect(gemmaResponder.capturedQuestion == "What is Tungsten?")
        try expect(gemmaResponder.capturedPageContext == pageContext)
    }

    static func testProviderBackedResponderUsesCodexACPResponder() async throws {
        let appleResponder = RecordingLocalAI(result: .answered("Apple sidebar answer"))
        let codexResponder = RecordingLocalAI(result: .answered("Codex sidebar answer"))
        let responder = ProviderBackedLocalAIResponder(
            provider: { .codexACP },
            appleResponder: appleResponder,
            codexResponder: codexResponder
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .answered("Codex sidebar answer"))
        try expect(appleResponder.capturedQuestion == nil)
        try expect(codexResponder.capturedQuestion == "What is Tungsten?")
    }

    static func testProviderBackedResponderReportsDisabledProvider() async throws {
        let responder = ProviderBackedLocalAIResponder(
            provider: { .disabled },
            appleResponder: StubLocalAI(result: .answered("Stub answer"))
        )

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .unavailable("Local AI is disabled, so Tungsten opened AI search instead."))
    }

    static func testGemmaManagerWarnsBeforeLiteRTDownload() async throws {
        let modelDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: URL(fileURLWithPath: "/tmp/tungsten-missing-litert-runtime"),
            modelDirectoryURL: modelDirectoryURL,
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!
        )
        let manager = GemmaLocalAIModelManager(configuration: configuration)

        let availability = await manager.availability()

        try expect(availability.state == .downloadable)
        try expect(availability.message.contains("download"))
        try expect(availability.message.contains("2.6 GB"))
        try expect(availability.message.contains("LiteRT"))
    }

    static func testGemmaManagerOffersRuntimeRepairWhenModelIsInstalled() async throws {
        let modelDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtimeURL = modelDirectoryURL.appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: runtimeURL,
            modelDirectoryURL: modelDirectoryURL,
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!,
            runtimeSupportLibraryDownloadURLs: [],
            modelFilename: "model.litertlm"
        )
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: configuration.modelURL.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: modelDirectoryURL)
        }
        let manager = GemmaLocalAIModelManager(configuration: configuration)

        let availability = await manager.availability()

        try expect(availability.state == .downloadable)
        try expect(availability.message.contains("runtime"))
        try expect(availability.message.contains("2.6 GB") == false)
    }

    static func testGemmaManagerInstallsLiteRTLibraryWithoutRedownloadingModel() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDirectoryURL = rootURL.appendingPathComponent("models", isDirectory: true)
        let runtimeDirectoryURL = rootURL.appendingPathComponent("runtime", isDirectory: true)
        let runtimeURL = runtimeDirectoryURL.appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
        let runtimeSourceURL = rootURL.appendingPathComponent("liblitert-lm.dylib.download", isDirectory: false)
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: runtimeURL,
            modelDirectoryURL: modelDirectoryURL,
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!,
            runtimeDownloadURL: URL(string: "https://example.com/liblitert-lm.dylib")!,
            runtimeSupportLibraryDownloadURLs: [],
            modelFilename: "model.litertlm"
        )
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: configuration.modelURL.path, contents: Data())
        FileManager.default.createFile(atPath: runtimeSourceURL.path, contents: Data([1, 2, 3]))
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let manager = GemmaLocalAIModelManager(
            configuration: configuration,
            downloadFile: { url in
                if url == configuration.runtimeDownloadURL {
                    return runtimeSourceURL
                }
                throw TestFailure()
            }
        )

        let availability = await manager.prepare()

        try expect(availability.state == .available)
        try expect(FileManager.default.fileExists(atPath: runtimeURL.path))
        try expect(FileManager.default.isExecutableFile(atPath: runtimeURL.path) == false)
        try expect(FileManager.default.fileExists(atPath: configuration.modelURL.path))
    }

    static func testGemmaManagerExtractsLiteRTLibraryFromWheel() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDirectoryURL = rootURL.appendingPathComponent("models", isDirectory: true)
        let runtimeURL = rootURL
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
        let wheelURL = try createFakeLiteRTWheel(rootURL: rootURL, contents: Data([9, 8, 7]))
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: runtimeURL,
            modelDirectoryURL: modelDirectoryURL,
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!,
            runtimeDownloadURL: URL(string: "https://example.com/litert_lm_api.whl")!,
            runtimeSupportLibraryDownloadURLs: [],
            modelFilename: "model.litertlm"
        )
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: configuration.modelURL.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let manager = GemmaLocalAIModelManager(
            configuration: configuration,
            downloadFile: { url in
                if url == configuration.runtimeDownloadURL {
                    return wheelURL
                }
                throw TestFailure()
            }
        )

        let availability = await manager.prepare()
        let runtimeData = try Data(contentsOf: runtimeURL)

        try expect(availability.state == .available)
        try expect(runtimeData == Data([9, 8, 7]))
    }

    static func testGemmaResponderReportsMissingRuntimeBeforeDownload() async throws {
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: URL(fileURLWithPath: "/tmp/tungsten-missing-litert-runtime"),
            modelDirectoryURL: URL(fileURLWithPath: "/tmp/tungsten-missing-models"),
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!
        )
        let responder = GemmaLocalAIResponder(configuration: configuration)

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .unavailable("Gemma LiteRT Local needs the LiteRT runtime before it can answer locally."))
    }

    static func testGemmaResponderTrimsLiteRTOutput() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = try installedGemmaConfiguration(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let responder = GemmaLocalAIResponder(configuration: configuration, answerRunner: { _, _ in
            """
              <|channel>final
            100
            """
        })

        let result = await responder.answer("What is 10 times 10?")

        try expect(result == .answered("100"))
    }

    static func testGemmaResponderStreamsPartialAnswers() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = try installedGemmaConfiguration(rootURL: rootURL)
        final class Capture: @unchecked Sendable {
            var partials = [String]()
        }
        let capture = Capture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let responder = GemmaLocalAIResponder(
            configuration: configuration,
            answerRunner: { _, _ in "Final answer" },
            streamRunner: { _, _, onPartialAnswer in
                await onPartialAnswer("Final")
                await onPartialAnswer("Final answer")
                return "Final answer"
            }
        )

        let result = await responder.answer(
            "What is Tungsten?",
            pageContext: nil,
            onPartialAnswer: { partial in
                capture.partials.append(partial)
            }
        )

        try expect(result == .answered("Final answer"))
        try expect(capture.partials == ["Final", "Final answer"])
    }

    static func testGemmaResponderUsesNativeRuntimeWithSystemInstructionsAndUserPrompt() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = try installedGemmaConfiguration(rootURL: rootURL)
        let pageContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com/docs",
            selectedText: "Selected text",
            bodyText: "Full page text"
        )
        final class Capture: @unchecked Sendable {
            var prompt: String?
            var instructions: String?
        }
        let capture = Capture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let responder = GemmaLocalAIResponder(configuration: configuration, answerRunner: { prompt, instructions in
            capture.prompt = prompt
            capture.instructions = instructions
            return "Native answer"
        })

        let result = await responder.answer("What changed?", pageContext: pageContext)

        try expect(result == .answered("Native answer"))
        try expect(capture.instructions == LocalAIPrompts.instructions(hasPageContext: true))
        try expect(capture.prompt?.hasPrefix("Question:\nWhat changed?") == true)
        try expect(capture.prompt?.contains("Current page:") == true)
        try expect(capture.prompt?.contains(LocalAIPrompts.instructions(hasPageContext: true)) == false)
    }

    static func testGemmaResponderStripsLiteRTPromptEchoAndBenchmarkInfo() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = try installedGemmaConfiguration(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let responder = GemmaLocalAIResponder(configuration: configuration, answerRunner: { prompt, _ in
            """
            input_prompt: \(prompt)
            4132.5

            BenchmarkInfo:
              Init Phases (7):
                - Init Executor: 1685.19 ms
            --------------------------------------------------
            """
        })

        let result = await responder.answer("25 times 165.3", pageContext: nil)

        try expect(result == .answered("4132.5"))
    }

    static func testGemmaResponderRejectsRuntimeShellTranscript() async throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = try installedGemmaConfiguration(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let shellTranscript = """
        Loading model... |\\b-\\b\\\\\\b|\\b/\\b
        available commands:
          /exit or Ctrl+C     stop or exit

        >

        >

        >

        Exiting...
        """
        let responder = GemmaLocalAIResponder(configuration: configuration, answerRunner: { _, _ in
            shellTranscript
        })

        let result = await responder.answer("What is Tungsten?")

        try expect(result == .unavailable("Gemma LiteRT Local returned runtime output instead of an answer, so Tungsten opened AI search instead."))
    }

    static func testACPClientCreatesSessionWithBrowserAssistantCapabilities() async throws {
        let transport = FakeACPTransport(messages: [
            .response(id: 1, result: [
                "protocolVersion": 1,
                "agentCapabilities": [:],
                "authMethods": []
            ]),
            .response(id: 2, result: [
                "sessionId": "session-1"
            ]),
            .response(id: 3, result: [
                "stopReason": "end_turn"
            ])
        ])
        let client = ACPClient(
            transport: transport,
            cwd: URL(fileURLWithPath: "/tmp/tungsten-acp", isDirectory: true)
        )

        _ = try await client.answer("Hello", onPartialText: { _ in })

        let sent = await transport.sentMessages
        try expect(sent.count == 3)
        try expect(sent[0]["method"] as? String == "initialize")
        let initializeParams = try requireDictionary(sent[0]["params"])
        try expect(initializeParams["protocolVersion"] as? Int == 1)
        let capabilities = try requireDictionary(initializeParams["clientCapabilities"])
        let fs = try requireDictionary(capabilities["fs"])
        try expect(fs["readTextFile"] as? Bool == false)
        try expect(fs["writeTextFile"] as? Bool == false)
        try expect(capabilities["terminal"] as? Bool == false)

        try expect(sent[1]["method"] as? String == "session/new")
        let sessionParams = try requireDictionary(sent[1]["params"])
        try expect(sessionParams["cwd"] as? String == "/tmp/tungsten-acp")
        try expect((sessionParams["mcpServers"] as? [Any])?.isEmpty == true)

        try expect(sent[2]["method"] as? String == "session/prompt")
        let promptParams = try requireDictionary(sent[2]["params"])
        try expect(promptParams["sessionId"] as? String == "session-1")
        let prompt = try requireArray(promptParams["prompt"])
        let firstBlock = try requireDictionary(prompt.first)
        try expect(firstBlock["type"] as? String == "text")
        try expect(firstBlock["text"] as? String == "Hello")
    }

    static func testACPClientStreamsAgentMessageChunks() async throws {
        let transport = FakeACPTransport(messages: [
            .response(id: 1, result: [
                "protocolVersion": 1,
                "agentCapabilities": [:],
                "authMethods": []
            ]),
            .response(id: 2, result: [
                "sessionId": "session-1"
            ]),
            .notification(method: "session/update", params: [
                "sessionId": "session-1",
                "update": [
                    "sessionUpdate": "agent_message_chunk",
                    "content": ["type": "text", "text": "Hello"]
                ]
            ]),
            .notification(method: "session/update", params: [
                "sessionId": "session-1",
                "update": [
                    "sessionUpdate": "agent_message_chunk",
                    "content": ["type": "text", "text": ", page"]
                ]
            ]),
            .response(id: 3, result: [
                "stopReason": "end_turn"
            ])
        ])
        let client = ACPClient(
            transport: transport,
            cwd: URL(fileURLWithPath: "/tmp/tungsten-acp", isDirectory: true)
        )
        final class Capture: @unchecked Sendable {
            var partials = [String]()
        }
        let capture = Capture()

        let answer = try await client.answer("Summarize", onPartialText: { partial in
            capture.partials.append(partial)
        })

        try expect(answer == "Hello, page")
        try expect(capture.partials == ["Hello", "Hello, page"])
    }

    static func testACPAgentResponderStreamsPageAwareAnswer() async throws {
        let fakeClient = FakeACPAnswerClient(answer: "Page summary", partials: ["Page", "Page summary"])
        let responder = ACPAgentResponder(
            providerName: "Codex via ACP",
            configuration: .codexDefault,
            clientFactory: { _ in fakeClient }
        )
        let pageContext = PageContentContext(
            title: "Article",
            urlString: "https://example.com/article",
            selectedText: nil,
            bodyText: "Tungsten is a thread-first browser."
        )
        final class Capture: @unchecked Sendable {
            var partials = [String]()
        }
        let capture = Capture()

        let result = await responder.answer(
            "Summarize this page",
            pageContext: pageContext,
            onPartialAnswer: { partial in
                capture.partials.append(partial)
            }
        )

        try expect(result == .answered("Page summary"))
        try expect(capture.partials == ["Page", "Page summary"])
        let prompt = await fakeClient.capturedPrompt ?? ""
        try expect(prompt.contains("Use the current-page context first"))
        try expect(prompt.contains("Current page:"))
        try expect(prompt.contains("Title: Article"))
        try expect(prompt.contains("Tungsten is a thread-first browser."))
    }

    static func testACPAgentResponderReusesSessionClient() async throws {
        let factory = CountingACPClientFactory(answer: "Session answer")
        let responder = ACPAgentResponder(
            providerName: "Codex via ACP",
            configuration: .codexDefault,
            clientFactory: { configuration in
                try factory.makeClient(configuration)
            }
        )

        let first = await responder.answer("First question", pageContext: nil)
        let second = await responder.answer("Second question", pageContext: nil)

        try expect(first == .answered("Session answer"))
        try expect(second == .answered("Session answer"))
        try expect(factory.makeCount == 1)
        let prompts = await factory.client.capturedPrompts
        try expect(prompts.count == 2)
        try expect(prompts[0].contains("First question"))
        try expect(prompts[1].contains("Second question"))
    }

    static func testACPAgentResponderReportsStartupFailure() async throws {
        let responder = ACPAgentResponder(
            providerName: "Codex via ACP",
            configuration: .codexDefault,
            clientFactory: { _ in
                throw ACPClientError.processUnavailable("Unable to start codex.")
            }
        )

        let result = await responder.answer("Hello", pageContext: nil)

        try expect(result == .unavailable("Codex via ACP is unavailable. Check the command in Settings."))
    }

    static func testCodexACPDefaultsUseAdapterCommand() throws {
        try expect(ACPProviderConfiguration.codexDefault.command == "codex-acp")
        try expect(ACPProviderConfiguration.codexDefault.arguments.contains("acp") == false)
    }

    static func testCodexACPLaunchConfigurationDisablesInheritedMCPServers() throws {
        let launch = ACPAgentResponder.launchConfiguration(
            for: .codexDefault,
            disabledMCPServerNames: ["linear"],
            disabledPluginNames: ["slack@openai-curated"]
        )

        try expect(launch.command == "codex-acp")
        try expect(launch.arguments.contains("mcp_servers.linear.enabled=false"))
        try expect(launch.arguments.contains("mcp_oauth_credentials_store=\"file\""))
        try expect(launch.arguments.contains("plugins.\"slack@openai-curated\".enabled=false"))
    }

    static func testACPTransportFindsZedExternalAgent() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let adapterURL = rootURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zed", isDirectory: true)
            .appendingPathComponent("external_agents", isDirectory: true)
            .appendingPathComponent("registry", isDirectory: true)
            .appendingPathComponent("codex-acp", isDirectory: true)
            .appendingPathComponent("v_0.1.0_test", isDirectory: true)
            .appendingPathComponent("codex-acp", isDirectory: false)
        try FileManager.default.createDirectory(
            at: adapterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: adapterURL.path, contents: Data([1, 2, 3]))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapterURL.path)
        try expect(FileManager.default.isExecutableFile(atPath: adapterURL.path))

        let resolvedURL = ACPStdioTransport.executableURL(
            for: "codex-acp",
            environment: ["PATH": ""],
            homeDirectory: rootURL
        )

        try expect(resolvedURL.standardizedFileURL.path == adapterURL.standardizedFileURL.path)
    }

    static func testGemmaRuntimeDefaultsUseLiteRTLibraryWheel() throws {
        try expect(GemmaLocalAIConfiguration.defaultRuntimeURL.lastPathComponent == "liblitert-lm.dylib")
        try expect(GemmaLocalAIConfiguration.defaultRuntimeDownloadURL.lastPathComponent.hasSuffix(".whl"))
    }

    static func testPagePromptFallsBackToGeneralKnowledge() throws {
        let instructions = LocalAIPrompts.instructions(hasPageContext: true)

        try expect(instructions.contains("answer as a general question"))
        try expect(instructions.contains("Do not invent page-specific facts or URLs."))
    }

    static func testPageContextOnlyAttachesForPageAwareQuestions() throws {
        let context = PageContentContext(
            title: "Long article",
            urlString: "https://example.com/article",
            selectedText: nil,
            bodyText: "Article body"
        )

        try expect(context.shouldAttach(to: "summarize this page"))
        try expect(context.shouldAttach(to: "what does this article say about tungsten?"))
        try expect(context.shouldAttach(to: "what is tungsten?") == false)
        try expect(context.shouldAttach(to: "ten times ten") == false)
    }

    static func testPageContextPrefersSelectedTextAndCapsContent() throws {
        let longBody = String(repeating: "x", count: PageContentContext.maxContentCharacters + 10)
        let selectedContext = PageContentContext(
            title: " Docs ",
            urlString: " https://example.com ",
            selectedText: "  Selected text  ",
            bodyText: longBody
        )
        let bodyOnlyContext = PageContentContext(
            title: "Docs",
            urlString: "https://example.com",
            selectedText: " ",
            bodyText: longBody
        )

        try expect(selectedContext.preferredText == "Selected text")
        try expect(selectedContext.usesSelectedText)
        try expect(bodyOnlyContext.preferredText?.count == PageContentContext.maxContentCharacters)
        try expect(bodyOnlyContext.usesSelectedText == false)
        try expect(selectedContext.prompt(for: "Summarize").contains("Selected page text:"))
    }

    static func expect(
        _ condition: @autoclosure () -> Bool,
        file: StaticString = #fileID,
        line: UInt = #line
    ) throws {
        if condition() == false {
            throw TestFailure(file: String(describing: file), line: line)
        }
    }

    static func requireDictionary(_ value: Any?) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw TestFailure()
        }
        return dictionary
    }

    static func requireArray(_ value: Any?) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw TestFailure()
        }
        return array
    }

    static func installedGemmaConfiguration(rootURL: URL) throws -> GemmaLocalAIConfiguration {
        let runtimeURL = rootURL
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
        let modelDirectoryURL = rootURL.appendingPathComponent("models", isDirectory: true)
        let configuration = GemmaLocalAIConfiguration(
            runtimeURL: runtimeURL,
            modelDirectoryURL: modelDirectoryURL,
            modelDownloadURL: URL(string: "https://example.com/gemma.litertlm")!,
            runtimeSupportLibraryDownloadURLs: [],
            modelFilename: "model.litertlm"
        )
        try FileManager.default.createDirectory(at: runtimeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runtimeURL.path, contents: Data([1, 2, 3]))
        FileManager.default.createFile(atPath: configuration.modelURL.path, contents: Data([4, 5, 6]))
        return configuration
    }

    static func createFakeLiteRTWheel(rootURL: URL, contents: Data) throws -> URL {
        let sourceRootURL = rootURL.appendingPathComponent("wheel-source", isDirectory: true)
        let libraryURL = sourceRootURL
            .appendingPathComponent("litert_lm", isDirectory: true)
            .appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
        try FileManager.default.createDirectory(
            at: libraryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: libraryURL)

        let wheelURL = rootURL.appendingPathComponent("litert_lm_api.whl", isDirectory: false)
        let process = Process()
        process.currentDirectoryURL = sourceRootURL
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip", isDirectory: false)
        process.arguments = [
            "-q",
            wheelURL.path,
            "litert_lm/liblitert-lm.dylib"
        ]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0)
        return wheelURL
    }
}

private struct StubLocalAI: LocalAIAnswering {
    let result: LocalAIResult

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        result
    }
}

private struct StreamingLocalAI: LocalAIAnswering {
    let result: LocalAIResult
    let partials: [String]

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        result
    }

    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @Sendable (String) async -> Void
    ) async -> LocalAIResult {
        for partial in partials {
            await onPartialAnswer(partial)
        }
        return result
    }
}

private final class RecordingLocalAI: LocalAIAnswering, @unchecked Sendable {
    let result: LocalAIResult
    var capturedQuestion: String?
    var capturedPageContext: PageContentContext?

    init(result: LocalAIResult) {
        self.result = result
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        capturedQuestion = question
        capturedPageContext = pageContext
        return result
    }
}

private final class RecordingSequenceLocalAI: LocalAIAnswering, @unchecked Sendable {
    private var results: [LocalAIResult]
    private(set) var capturedPageContexts = [PageContentContext?]()

    init(results: [LocalAIResult]) {
        self.results = results
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        capturedPageContexts.append(pageContext)
        return results.removeFirst()
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let file: String
    let line: UInt

    init(file: String = #fileID, line: UInt = #line) {
        self.file = file
        self.line = line
    }

    var description: String {
        "\(file):\(line)"
    }
}

private enum FakeACPMessage {
    case response(id: Int, result: [String: Any])
    case notification(method: String, params: [String: Any])

    var object: [String: Any] {
        switch self {
        case .response(let id, let result):
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": result
            ]
        case .notification(let method, let params):
            return [
                "jsonrpc": "2.0",
                "method": method,
                "params": params
            ]
        }
    }
}

private actor FakeACPTransport: ACPTransport {
    private var messages: [FakeACPMessage]
    private(set) var sentMessages = [[String: Any]]()

    init(messages: [FakeACPMessage]) {
        self.messages = messages
    }

    func send(_ message: [String: Any]) async throws {
        sentMessages.append(message)
    }

    func receive() async throws -> [String: Any]? {
        guard messages.isEmpty == false else {
            return nil
        }
        return messages.removeFirst().object
    }

    nonisolated func close() {}
}

private actor FakeACPAnswerClient: ACPAgentAnsweringClient {
    let answer: String
    let partials: [String]
    private(set) var capturedPrompts = [String]()
    var capturedPrompt: String? {
        capturedPrompts.last
    }

    init(answer: String, partials: [String] = []) {
        self.answer = answer
        self.partials = partials
    }

    func answer(
        _ prompt: String,
        onPartialText: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        capturedPrompts.append(prompt)
        for partial in partials {
            await onPartialText(partial)
        }
        return answer
    }

    func cancel() async {}

    func close() async {}
}

private final class CountingACPClientFactory: @unchecked Sendable {
    let client: FakeACPAnswerClient
    private let lock = NSLock()
    private var count = 0

    init(answer: String) {
        client = FakeACPAnswerClient(answer: answer)
    }

    var makeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func makeClient(_ configuration: ACPProviderConfiguration) throws -> any ACPAgentAnsweringClient {
        lock.lock()
        count += 1
        lock.unlock()
        return client
    }
}
