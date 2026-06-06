import Darwin
import Foundation

struct GemmaLocalAIConfiguration: Sendable {
    var runtimeURL: URL
    var modelDirectoryURL: URL
    var modelDownloadURL: URL
    var runtimeDownloadURL: URL
    var runtimeSupportLibraryDownloadURLs: [URL]
    var modelFilename: String
    var modelDisplayName: String
    var downloadWarning: String
    var isSupportedPlatform: Bool

    init(
        runtimeURL: URL = Self.defaultRuntimeURL,
        modelDirectoryURL: URL = Self.defaultModelDirectoryURL,
        modelDownloadURL: URL = Self.defaultModelDownloadURL,
        runtimeDownloadURL: URL = Self.defaultRuntimeDownloadURL,
        runtimeSupportLibraryDownloadURLs: [URL] = Self.defaultRuntimeSupportLibraryDownloadURLs,
        modelFilename: String = "gemma-4-E2B-it.litertlm",
        modelDisplayName: String = "Gemma 4 E2B LiteRT",
        downloadWarning: String = "Downloads about 2.6 GB of model files plus the LiteRT runtime.",
        isSupportedPlatform: Bool = Self.defaultIsSupportedPlatform
    ) {
        self.runtimeURL = runtimeURL
        self.modelDirectoryURL = modelDirectoryURL
        self.modelDownloadURL = modelDownloadURL
        self.runtimeDownloadURL = runtimeDownloadURL
        self.runtimeSupportLibraryDownloadURLs = runtimeSupportLibraryDownloadURLs
        self.modelFilename = modelFilename
        self.modelDisplayName = modelDisplayName
        self.downloadWarning = downloadWarning
        self.isSupportedPlatform = isSupportedPlatform
    }

    var modelURL: URL {
        modelDirectoryURL.appendingPathComponent(modelFilename, isDirectory: false)
    }

    var runtimeDirectoryURL: URL {
        runtimeURL.deletingLastPathComponent()
    }

    var runtimeSupportLibraryURLs: [URL] {
        runtimeSupportLibraryDownloadURLs.map { downloadURL in
            runtimeDirectoryURL.appendingPathComponent(downloadURL.lastPathComponent, isDirectory: false)
        }
    }

    static var defaultRuntimeURL: URL {
        defaultRuntimeDirectoryURL.appendingPathComponent("liblitert-lm.dylib", isDirectory: false)
    }

    static var defaultModelDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("Tungsten", isDirectory: true)
            .appendingPathComponent("LocalAI", isDirectory: true)
            .appendingPathComponent("GemmaLiteRT", isDirectory: true)
    }

    static var defaultRuntimeDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("Tungsten", isDirectory: true)
            .appendingPathComponent("LocalAI", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("litert-lm-v0.11.0", isDirectory: true)
    }

    static let defaultModelDownloadURL = URL(
        string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true"
    )!

    static let defaultRuntimeDownloadURL = URL(
        string: "https://files.pythonhosted.org/packages/87/ff/2ab25cb1bdd4ebcf20f1f4524e51c54e9f498e0775fa417b2a4bf33f37e6/litert_lm_api-0.11.0-py3-none-macosx_12_0_arm64.whl"
    )!

    static let defaultRuntimeSupportLibraryDownloadURLs: [URL] = []

    static var defaultIsSupportedPlatform: Bool {
        currentMachineArchitecture == "arm64"
    }

    private static var currentMachineArchitecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "arm64"
            }
        }
    }
}

protocol GemmaLocalAIManaging: Sendable {
    func availability() async -> GemmaLocalAIAvailability
    func prepare() async -> GemmaLocalAIAvailability
}

struct GemmaLocalAIModelManager: GemmaLocalAIManaging {
    var configuration: GemmaLocalAIConfiguration
    private let downloadFile: @Sendable (URL) async throws -> URL

    init(
        configuration: GemmaLocalAIConfiguration = GemmaLocalAIConfiguration(),
        downloadFile: (@Sendable (URL) async throws -> URL)? = nil
    ) {
        self.configuration = configuration
        self.downloadFile = downloadFile ?? { url in
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) == false {
                throw GemmaLocalAIError.downloadFailed(httpResponse.statusCode)
            }
            return temporaryURL
        }
    }

    func availability() async -> GemmaLocalAIAvailability {
        guard configuration.isSupportedPlatform else {
            return GemmaLocalAIAvailability(
                state: .unavailable,
                progress: nil,
                message: "Gemma LiteRT Local currently requires Apple Silicon macOS."
            )
        }

        let fileManager = FileManager.default
        let hasModel = fileManager.fileExists(atPath: configuration.modelURL.path)
        let hasRuntime = runtimeBundleIsInstalled(fileManager: fileManager)

        if hasModel && hasRuntime {
            return GemmaLocalAIAvailability(
                state: .available,
                progress: 1,
                message: "\(configuration.modelDisplayName) is ready for local sidebar answers."
            )
        }

        if hasModel {
            return GemmaLocalAIAvailability(
                state: .downloadable,
                progress: nil,
                message: "Gemma LiteRT Local model is installed. Download the LiteRT runtime to enable local answers."
            )
        }

        return GemmaLocalAIAvailability(
            state: .downloadable,
            progress: nil,
            message: "Gemma LiteRT Local needs a one-time download. \(configuration.downloadWarning)"
        )
    }

    func prepare() async -> GemmaLocalAIAvailability {
        let fileManager = FileManager.default
        let currentAvailability = await availability()
        if currentAvailability.state == .available || currentAvailability.state == .unavailable {
            return currentAvailability
        }

        do {
            if runtimeBundleIsInstalled(fileManager: fileManager) == false {
                try await installRuntime()
            }

            if fileManager.fileExists(atPath: configuration.modelURL.path) == false {
                try await installModel()
            }

            return await availability()
        } catch {
            return GemmaLocalAIAvailability(
                state: .unavailable,
                progress: nil,
                message: "Gemma LiteRT Local could not finish setup. \(error.localizedDescription)"
            )
        }
    }

    private func runtimeBundleIsInstalled(fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: configuration.runtimeURL.path)
            && configuration.runtimeSupportLibraryURLs.allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    private func installModel() async throws {
        let temporaryURL = try await downloadFile(configuration.modelDownloadURL)
        try installDownloadedFile(
            temporaryURL,
            destinationURL: configuration.modelURL,
            executable: false
        )
    }

    private func installRuntime() async throws {
        try FileManager.default.createDirectory(
            at: configuration.runtimeDirectoryURL,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: configuration.runtimeURL.path) == false {
            let temporaryURL = try await downloadFile(configuration.runtimeDownloadURL)
            try await installRuntimeLibrary(temporaryURL)
        }

        for supportLibraryDownloadURL in configuration.runtimeSupportLibraryDownloadURLs {
            let destinationURL = configuration.runtimeDirectoryURL
                .appendingPathComponent(supportLibraryDownloadURL.lastPathComponent, isDirectory: false)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                continue
            }

            let temporaryURL = try await downloadFile(supportLibraryDownloadURL)
            try installDownloadedFile(
                temporaryURL,
                destinationURL: destinationURL,
                executable: false
            )
        }
    }

    private func installRuntimeLibrary(_ downloadedURL: URL) async throws {
        if configuration.runtimeDownloadURL.pathExtension.lowercased() == "whl" {
            try await extractRuntimeLibrary(from: downloadedURL)
            return
        }

        try installDownloadedFile(
            downloadedURL,
            destinationURL: configuration.runtimeURL,
            executable: false
        )
    }

    private func extractRuntimeLibrary(from wheelURL: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configuration.runtimeDirectoryURL,
            withIntermediateDirectories: true
        )

        let partialURL = configuration.runtimeURL.appendingPathExtension("download")
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        fileManager.createFile(atPath: partialURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: partialURL)
        defer {
            try? outputHandle.close()
        }

        let process = Process()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip", isDirectory: false)
        process.arguments = [
            "-p",
            wheelURL.path,
            "litert_lm/liblitert-lm.dylib"
        ]
        process.standardOutput = outputHandle
        process.standardError = standardError

        let errorTask = Task.detached(priority: .utility) {
            standardError.fileHandleForReading.readDataToEndOfFile()
        }

        try process.run()
        process.waitUntilExit()
        let errorData = await errorTask.value

        guard process.terminationStatus == 0 else {
            try? fileManager.removeItem(at: partialURL)
            let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
            throw GemmaLocalAIError.runtimeArchiveExtractionFailed(errorMessage)
        }

        if fileManager.fileExists(atPath: configuration.runtimeURL.path) {
            try fileManager.removeItem(at: configuration.runtimeURL)
        }
        try fileManager.moveItem(at: partialURL, to: configuration.runtimeURL)
    }

    private func installDownloadedFile(
        _ downloadedURL: URL,
        destinationURL: URL,
        executable: Bool
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let partialURL = destinationURL.appendingPathExtension("download")
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }

        try fileManager.moveItem(at: downloadedURL, to: partialURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: partialURL, to: destinationURL)

        if executable {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }
    }
}

struct GemmaLocalAIResponder: LocalAIAnswering {
    private static let maxRuntimeOutputCharacters = 20_000

    var configuration: GemmaLocalAIConfiguration
    private let answerRunner: @Sendable (String, String) async throws -> String
    private let streamRunner: @Sendable (String, String, @escaping @Sendable (String) async -> Void) async throws -> String

    init(
        configuration: GemmaLocalAIConfiguration = GemmaLocalAIConfiguration(),
        answerRunner: (@Sendable (String, String) async throws -> String)? = nil,
        streamRunner: (@Sendable (String, String, @escaping @Sendable (String) async -> Void) async throws -> String)? = nil
    ) {
        self.configuration = configuration
        self.answerRunner = answerRunner ?? { prompt, instructions in
            try await GemmaLiteRTLMEnginePool.shared.answer(
                prompt: prompt,
                instructions: instructions,
                configuration: configuration
            )
        }
        self.streamRunner = streamRunner ?? { prompt, instructions, onPartialAnswer in
            try await GemmaLiteRTLMEnginePool.shared.answer(
                prompt: prompt,
                instructions: instructions,
                configuration: configuration,
                onPartialAnswer: onPartialAnswer
            )
        }
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        let fileManager = FileManager.default
        if let readinessError = readinessError(fileManager: fileManager) {
            return .unavailable(readinessError)
        }

        let instructions = LocalAIPrompts.instructions(hasPageContext: pageContext != nil)
        let prompt = Self.prompt(question: question, pageContext: pageContext)

        do {
            let answer = try await answerRunner(prompt, instructions)
            guard let normalizedAnswer = Self.normalizedAnswer(answer, prompt: prompt) else {
                return .unavailable("Gemma LiteRT Local returned runtime output instead of an answer, so Tungsten opened AI search instead.")
            }
            guard normalizedAnswer.isEmpty == false else {
                return .unavailable("Gemma LiteRT Local returned an empty answer, so Tungsten opened AI search instead.")
            }
            return .answered(normalizedAnswer)
        } catch {
            return .unavailable("Gemma LiteRT Local could not answer, so Tungsten opened AI search instead.")
        }
    }

    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async -> LocalAIResult {
        let fileManager = FileManager.default
        if let readinessError = readinessError(fileManager: fileManager) {
            return .unavailable(readinessError)
        }

        let instructions = LocalAIPrompts.instructions(hasPageContext: pageContext != nil)
        let prompt = Self.prompt(question: question, pageContext: pageContext)

        do {
            let answer = try await streamRunner(prompt, instructions) { partial in
                if let normalizedPartial = Self.normalizedAnswer(partial, prompt: prompt),
                   normalizedPartial.isEmpty == false {
                    await onPartialAnswer(normalizedPartial)
                }
            }
            guard let normalizedAnswer = Self.normalizedAnswer(answer, prompt: prompt) else {
                return .unavailable("Gemma LiteRT Local returned runtime output instead of an answer, so Tungsten opened AI search instead.")
            }
            guard normalizedAnswer.isEmpty == false else {
                return .unavailable("Gemma LiteRT Local returned an empty answer, so Tungsten opened AI search instead.")
            }
            return .answered(normalizedAnswer)
        } catch {
            return .unavailable("Gemma LiteRT Local could not answer, so Tungsten opened AI search instead.")
        }
    }

    private func readinessError(fileManager: FileManager) -> String? {
        guard fileManager.fileExists(atPath: configuration.runtimeURL.path) else {
            return "Gemma LiteRT Local needs the LiteRT runtime before it can answer locally."
        }

        guard configuration.runtimeSupportLibraryURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return "Gemma LiteRT Local needs the LiteRT runtime before it can answer locally."
        }

        guard fileManager.fileExists(atPath: configuration.modelURL.path) else {
            return "Gemma LiteRT Local is not installed. Use Download to fetch about 2.6 GB of model files before asking local sidebar questions."
        }

        return nil
    }

    private static func prompt(question: String, pageContext: PageContentContext?) -> String {
        if let pageContext {
            return pageContext.prompt(for: question)
        }

        return [
            "Question:",
            question
        ].joined(separator: "\n")
    }

    private static func normalizedAnswer(_ value: String, prompt: String) -> String? {
        guard value.count <= maxRuntimeOutputCharacters,
              looksLikeRuntimeShellTranscript(value) == false else {
            return nil
        }

        var answer = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptEcho = "input_prompt: \(prompt)"
        if answer.hasPrefix(promptEcho) {
            answer = String(answer.dropFirst(promptEcho.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let benchmarkRange = answer.range(of: "\nBenchmarkInfo:") {
            answer = String(answer[..<benchmarkRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if answer.hasPrefix("BenchmarkInfo:") {
            answer = ""
        }
        if let thoughtEnd = answer.range(of: "<channel|>", options: .backwards) {
            answer = String(answer[thoughtEnd.upperBound...])
        }
        return answer
            .replacingOccurrences(of: "<|channel>final", with: "")
            .replacingOccurrences(of: "<|channel>analysis", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeRuntimeShellTranscript(_ value: String) -> Bool {
        let lowercasedValue = value.lowercased()
        guard lowercasedValue.contains("loading model")
                || lowercasedValue.contains("available commands:")
                || lowercasedValue.contains("exiting...") else {
            return false
        }

        var promptMarkerCount = 0
        var searchRange = value.startIndex..<value.endIndex
        while let range = value.range(of: "\n>", range: searchRange) {
            promptMarkerCount += 1
            if promptMarkerCount >= 3 {
                return true
            }
            searchRange = range.upperBound..<value.endIndex
        }

        return lowercasedValue.contains("available commands:")
            && lowercasedValue.contains("exiting...")
    }
}

private actor GemmaLiteRTLMEnginePool {
    static let shared = GemmaLiteRTLMEnginePool()

    private struct RuntimeKey: Equatable {
        var runtimePath: String
        var modelPath: String
        var cacheDirectoryPath: String
    }

    private var runtime: GemmaLiteRTLMRuntime?
    private var runtimeKey: RuntimeKey?

    func answer(
        prompt: String,
        instructions: String,
        configuration: GemmaLocalAIConfiguration
    ) throws -> String {
        let cacheDirectoryURL = configuration.modelDirectoryURL
        let key = RuntimeKey(
            runtimePath: configuration.runtimeURL.path,
            modelPath: configuration.modelURL.path,
            cacheDirectoryPath: cacheDirectoryURL.path
        )

        if runtimeKey != key {
            runtime = try GemmaLiteRTLMRuntime(
                runtimeURL: configuration.runtimeURL,
                modelURL: configuration.modelURL,
                cacheDirectoryURL: cacheDirectoryURL
            )
            runtimeKey = key
        }

        guard let runtime else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM engine is not initialized.")
        }

        return try runtime.answer(prompt: prompt, instructions: instructions)
    }

    func answer(
        prompt: String,
        instructions: String,
        configuration: GemmaLocalAIConfiguration,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let cacheDirectoryURL = configuration.modelDirectoryURL
        let key = RuntimeKey(
            runtimePath: configuration.runtimeURL.path,
            modelPath: configuration.modelURL.path,
            cacheDirectoryPath: cacheDirectoryURL.path
        )

        if runtimeKey != key {
            runtime = try GemmaLiteRTLMRuntime(
                runtimeURL: configuration.runtimeURL,
                modelURL: configuration.modelURL,
                cacheDirectoryURL: cacheDirectoryURL
            )
            runtimeKey = key
        }

        guard let runtime else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM engine is not initialized.")
        }

        return try await runtime.answer(
            prompt: prompt,
            instructions: instructions,
            onPartialAnswer: onPartialAnswer
        )
    }
}

private final class GemmaLiteRTLMRuntime: @unchecked Sendable {
    private let functions: GemmaLiteRTLMFunctions
    private let engine: OpaquePointer

    init(runtimeURL: URL, modelURL: URL, cacheDirectoryURL: URL) throws {
        let loadedFunctions = try GemmaLiteRTLMFunctions(runtimeURL: runtimeURL)
        try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)

        loadedFunctions.setMinLogLevel(4)

        let settings = try modelURL.path.withCString { modelPath in
            try "gpu".withCString { backend in
                guard let settings = loadedFunctions.engineSettingsCreate(modelPath, backend, nil, nil) else {
                    throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create engine settings.")
                }
                return settings
            }
        }
        defer {
            loadedFunctions.engineSettingsDelete(settings)
        }

        cacheDirectoryURL.path.withCString { cacheDirectoryPath in
            loadedFunctions.engineSettingsSetCacheDir(settings, cacheDirectoryPath)
        }

        guard let engine = loadedFunctions.engineCreate(settings) else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create the Gemma engine.")
        }
        self.functions = loadedFunctions
        self.engine = engine
    }

    deinit {
        functions.engineDelete(engine)
        functions.close()
    }

    func answer(prompt: String, instructions: String) throws -> String {
        let sessionConfig = try makeSessionConfig()
        defer {
            functions.sessionConfigDelete(sessionConfig)
        }

        guard let conversationConfig = functions.conversationConfigCreate() else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create a conversation config.")
        }
        defer {
            functions.conversationConfigDelete(conversationConfig)
        }

        functions.conversationConfigSetSessionConfig(conversationConfig, sessionConfig)

        let systemMessageJSON = try Self.systemMessageJSON(instructions)
        systemMessageJSON.withCString { systemMessage in
            functions.conversationConfigSetSystemMessage(conversationConfig, systemMessage)
        }
        functions.conversationConfigSetFilterChannelContentFromKVCache(conversationConfig, true)

        guard let conversation = functions.conversationCreate(engine, conversationConfig) else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create a conversation.")
        }
        defer {
            functions.conversationDelete(conversation)
        }

        let messageJSON = try Self.userMessageJSON(prompt)
        let response = try messageJSON.withCString { message in
            guard let response = functions.conversationSendMessage(conversation, message, nil) else {
                throw GemmaLocalAIError.runtimeFailed("LiteRT-LM did not return a response.")
            }
            return response
        }
        defer {
            functions.jsonResponseDelete(response)
        }

        guard let responseStringPointer = functions.jsonResponseGetString(response) else {
            throw GemmaLocalAIError.runtimeResponseMalformed
        }

        return try Self.answerText(from: String(cString: responseStringPointer))
    }

    func answer(
        prompt: String,
        instructions: String,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let sessionConfig = try makeSessionConfig()
        defer {
            functions.sessionConfigDelete(sessionConfig)
        }

        guard let conversationConfig = functions.conversationConfigCreate() else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create a conversation config.")
        }
        defer {
            functions.conversationConfigDelete(conversationConfig)
        }

        functions.conversationConfigSetSessionConfig(conversationConfig, sessionConfig)

        let systemMessageJSON = try Self.systemMessageJSON(instructions)
        systemMessageJSON.withCString { systemMessage in
            functions.conversationConfigSetSystemMessage(conversationConfig, systemMessage)
        }
        functions.conversationConfigSetFilterChannelContentFromKVCache(conversationConfig, true)

        guard let conversation = functions.conversationCreate(engine, conversationConfig) else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create a conversation.")
        }
        defer {
            functions.conversationDelete(conversation)
        }

        let messageJSON = try Self.userMessageJSON(prompt)
        guard let messageCString = strdup(messageJSON),
              let contextCString = strdup("{}") else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not allocate streaming request buffers.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let box = GemmaLiteRTLMStreamBox(
                messageCString: messageCString,
                contextCString: contextCString,
                continuation: continuation,
                onPartialAnswer: onPartialAnswer
            )
            let userData = Unmanaged.passRetained(box).toOpaque()

            let status = functions.conversationSendMessageStream(
                conversation,
                messageCString,
                contextCString,
                tungstenGemmaLiteRTLMStreamCallback,
                userData
            )

            if status != 0 {
                Unmanaged<GemmaLiteRTLMStreamBox>.fromOpaque(userData).release()
                continuation.resume(
                    throwing: GemmaLocalAIError.runtimeFailed(
                        "LiteRT-LM could not start streaming a response."
                    )
                )
            }
        }
    }

    private func makeSessionConfig() throws -> OpaquePointer {
        guard let sessionConfig = functions.sessionConfigCreate() else {
            throw GemmaLocalAIError.runtimeFailed("LiteRT-LM could not create a session config.")
        }
        functions.sessionConfigSetMaxOutputTokens(sessionConfig, 256)
        return sessionConfig
    }

    private static func systemMessageJSON(_ text: String) throws -> String {
        try jsonString(from: [
            "type": "text",
            "text": text
        ])
    }

    private static func userMessageJSON(_ text: String) throws -> String {
        try jsonString(from: [
            "role": "user",
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ]
        ])
    }

    fileprivate static func answerText(from responseJSON: String) throws -> String {
        guard let data = responseJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] else {
            throw GemmaLocalAIError.runtimeResponseMalformed
        }

        if let text = content as? String {
            return text
        }

        guard let parts = content as? [[String: Any]] else {
            throw GemmaLocalAIError.runtimeResponseMalformed
        }

        let text = parts.compactMap { part in
            part["text"] as? String
        }.joined()
        guard text.isEmpty == false else {
            throw GemmaLocalAIError.runtimeResponseMalformed
        }
        return text
    }

    private static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let value = String(data: data, encoding: .utf8) else {
            throw GemmaLocalAIError.runtimeResponseMalformed
        }
        return value
    }
}

@_cdecl("TungstenGemmaLiteRTLMStreamCallback")
func tungstenGemmaLiteRTLMStreamCallback(
    _ userData: UnsafeMutableRawPointer?,
    _ chunk: UnsafePointer<CChar>?,
    _ isFinal: Bool,
    _ error: UnsafePointer<CChar>?
) {
    guard let userData else {
        return
    }

    let box = Unmanaged<GemmaLiteRTLMStreamBox>.fromOpaque(userData).takeUnretainedValue()
    if box.handle(
        chunk: chunk.map { String(cString: $0) },
        isFinal: isFinal,
        errorMessage: error.map { String(cString: $0) }
    ) {
        Unmanaged<GemmaLiteRTLMStreamBox>.fromOpaque(userData).release()
    }
}

private final class GemmaLiteRTLMStreamBox: @unchecked Sendable {
    private let messageCString: UnsafeMutablePointer<CChar>
    private let contextCString: UnsafeMutablePointer<CChar>
    private let continuation: CheckedContinuation<String, Error>
    private let onPartialAnswer: @Sendable (String) async -> Void
    private let lock = NSLock()
    private var accumulatedAnswer = ""
    private var isCompleted = false

    init(
        messageCString: UnsafeMutablePointer<CChar>,
        contextCString: UnsafeMutablePointer<CChar>,
        continuation: CheckedContinuation<String, Error>,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) {
        self.messageCString = messageCString
        self.contextCString = contextCString
        self.continuation = continuation
        self.onPartialAnswer = onPartialAnswer
    }

    deinit {
        free(messageCString)
        free(contextCString)
    }

    func handle(chunk: String?, isFinal: Bool, errorMessage: String?) -> Bool {
        if let errorMessage, errorMessage.isEmpty == false {
            lock.lock()
            guard isCompleted == false else {
                lock.unlock()
                return false
            }
            isCompleted = true
            lock.unlock()

            continuation.resume(throwing: GemmaLocalAIError.runtimeFailed(errorMessage))
            return true
        }

        if let chunk,
           chunk.isEmpty == false,
           let chunkText = try? GemmaLiteRTLMRuntime.answerText(from: chunk),
           chunkText.isEmpty == false {
            let partial: String
            lock.lock()
            accumulatedAnswer += chunkText
            partial = accumulatedAnswer
            lock.unlock()

            Task {
                await onPartialAnswer(partial)
            }
        }

        guard isFinal else {
            return false
        }

        lock.lock()
        guard isCompleted == false else {
            lock.unlock()
            return false
        }
        isCompleted = true
        let answer = accumulatedAnswer
        lock.unlock()

        continuation.resume(returning: answer)
        return true
    }
}

private struct GemmaLiteRTLMFunctions {
    typealias SetMinLogLevel = @convention(c) (Int32) -> Void
    typealias EngineSettingsCreate = @convention(c) (
        UnsafePointer<CChar>,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> OpaquePointer?
    typealias EngineSettingsDelete = @convention(c) (OpaquePointer) -> Void
    typealias EngineSettingsSetCacheDir = @convention(c) (OpaquePointer, UnsafePointer<CChar>) -> Void
    typealias EngineCreate = @convention(c) (OpaquePointer) -> OpaquePointer?
    typealias EngineDelete = @convention(c) (OpaquePointer) -> Void
    typealias SessionConfigCreate = @convention(c) () -> OpaquePointer?
    typealias SessionConfigSetMaxOutputTokens = @convention(c) (OpaquePointer, Int32) -> Void
    typealias SessionConfigDelete = @convention(c) (OpaquePointer) -> Void
    typealias ConversationConfigCreate = @convention(c) () -> OpaquePointer?
    typealias ConversationConfigSetSessionConfig = @convention(c) (OpaquePointer, OpaquePointer) -> Void
    typealias ConversationConfigSetSystemMessage = @convention(c) (OpaquePointer, UnsafePointer<CChar>) -> Void
    typealias ConversationConfigSetFilterChannelContentFromKVCache = @convention(c) (OpaquePointer, Bool) -> Void
    typealias ConversationConfigDelete = @convention(c) (OpaquePointer) -> Void
    typealias ConversationCreate = @convention(c) (OpaquePointer, OpaquePointer) -> OpaquePointer?
    typealias ConversationDelete = @convention(c) (OpaquePointer) -> Void
    typealias ConversationSendMessage = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?
    ) -> OpaquePointer?
    typealias LiteRTLMStreamCallback = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        Bool,
        UnsafePointer<CChar>?
    ) -> Void
    typealias ConversationSendMessageStream = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?,
        LiteRTLMStreamCallback,
        UnsafeMutableRawPointer?
    ) -> Int32
    typealias JSONResponseDelete = @convention(c) (OpaquePointer) -> Void
    typealias JSONResponseGetString = @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?

    let handle: UnsafeMutableRawPointer
    let setMinLogLevel: SetMinLogLevel
    let engineSettingsCreate: EngineSettingsCreate
    let engineSettingsDelete: EngineSettingsDelete
    let engineSettingsSetCacheDir: EngineSettingsSetCacheDir
    let engineCreate: EngineCreate
    let engineDelete: EngineDelete
    let sessionConfigCreate: SessionConfigCreate
    let sessionConfigSetMaxOutputTokens: SessionConfigSetMaxOutputTokens
    let sessionConfigDelete: SessionConfigDelete
    let conversationConfigCreate: ConversationConfigCreate
    let conversationConfigSetSessionConfig: ConversationConfigSetSessionConfig
    let conversationConfigSetSystemMessage: ConversationConfigSetSystemMessage
    let conversationConfigSetFilterChannelContentFromKVCache: ConversationConfigSetFilterChannelContentFromKVCache
    let conversationConfigDelete: ConversationConfigDelete
    let conversationCreate: ConversationCreate
    let conversationDelete: ConversationDelete
    let conversationSendMessage: ConversationSendMessage
    let conversationSendMessageStream: ConversationSendMessageStream
    let jsonResponseDelete: JSONResponseDelete
    let jsonResponseGetString: JSONResponseGetString

    init(runtimeURL: URL) throws {
        guard let handle = dlopen(runtimeURL.path, RTLD_NOW | RTLD_LOCAL) else {
            throw GemmaLocalAIError.runtimeLibraryLoadFailed(Self.lastDynamicLoaderError())
        }

        do {
            self.handle = handle
            setMinLogLevel = try Self.load("litert_lm_set_min_log_level", from: handle)
            engineSettingsCreate = try Self.load("litert_lm_engine_settings_create", from: handle)
            engineSettingsDelete = try Self.load("litert_lm_engine_settings_delete", from: handle)
            engineSettingsSetCacheDir = try Self.load("litert_lm_engine_settings_set_cache_dir", from: handle)
            engineCreate = try Self.load("litert_lm_engine_create", from: handle)
            engineDelete = try Self.load("litert_lm_engine_delete", from: handle)
            sessionConfigCreate = try Self.load("litert_lm_session_config_create", from: handle)
            sessionConfigSetMaxOutputTokens = try Self.load("litert_lm_session_config_set_max_output_tokens", from: handle)
            sessionConfigDelete = try Self.load("litert_lm_session_config_delete", from: handle)
            conversationConfigCreate = try Self.load("litert_lm_conversation_config_create", from: handle)
            conversationConfigSetSessionConfig = try Self.load("litert_lm_conversation_config_set_session_config", from: handle)
            conversationConfigSetSystemMessage = try Self.load("litert_lm_conversation_config_set_system_message", from: handle)
            conversationConfigSetFilterChannelContentFromKVCache = try Self.load(
                "litert_lm_conversation_config_set_filter_channel_content_from_kv_cache",
                from: handle
            )
            conversationConfigDelete = try Self.load("litert_lm_conversation_config_delete", from: handle)
            conversationCreate = try Self.load("litert_lm_conversation_create", from: handle)
            conversationDelete = try Self.load("litert_lm_conversation_delete", from: handle)
            conversationSendMessage = try Self.load("litert_lm_conversation_send_message", from: handle)
            conversationSendMessageStream = try Self.load("litert_lm_conversation_send_message_stream", from: handle)
            jsonResponseDelete = try Self.load("litert_lm_json_response_delete", from: handle)
            jsonResponseGetString = try Self.load("litert_lm_json_response_get_string", from: handle)
        } catch {
            dlclose(handle)
            throw error
        }
    }

    func close() {
        dlclose(handle)
    }

    private static func load<T>(_ symbol: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let pointer = dlsym(handle, symbol) else {
            throw GemmaLocalAIError.runtimeLibraryMissingSymbol(symbol)
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func lastDynamicLoaderError() -> String {
        guard let error = dlerror() else {
            return "Unknown dynamic loader error."
        }
        return String(cString: error)
    }
}

enum GemmaLocalAIError: Error, LocalizedError, Equatable {
    case downloadFailed(Int)
    case runtimeFailed(String)
    case runtimeArchiveExtractionFailed(String)
    case runtimeLibraryLoadFailed(String)
    case runtimeLibraryMissingSymbol(String)
    case runtimeResponseMalformed

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let statusCode):
            return "Download failed with HTTP \(statusCode)."
        case .runtimeFailed(let message):
            return message.isEmpty
                ? "LiteRT-LM exited with an error."
                : message
        case .runtimeArchiveExtractionFailed(let message):
            return message.isEmpty
                ? "LiteRT-LM runtime archive extraction failed."
                : message
        case .runtimeLibraryLoadFailed(let message):
            return message.isEmpty
                ? "LiteRT-LM runtime library could not be loaded."
                : message
        case .runtimeLibraryMissingSymbol(let symbol):
            return "LiteRT-LM runtime library is missing \(symbol)."
        case .runtimeResponseMalformed:
            return "LiteRT-LM returned a malformed response."
        }
    }
}
