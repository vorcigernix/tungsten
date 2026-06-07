import Foundation

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

actor ACPClient {
    private let transport: ACPTransport
    private let cwd: URL
    private var nextRequestID = 1
    private var sessionID: String?

    init(transport: ACPTransport, cwd: URL = ACPClient.defaultCWD()) {
        self.transport = transport
        self.cwd = cwd
    }

    static func defaultCWD() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("Tungsten", isDirectory: true)
            .appendingPathComponent("ACP", isDirectory: true)
    }

    func answer(
        _ prompt: String,
        onPartialText: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let sessionID = try await ensureSession()
        var accumulatedText = ""

        _ = try await request(
            method: "session/prompt",
            params: [
                "sessionId": sessionID,
                "prompt": [
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ],
            onNotification: { message in
                guard let chunk = Self.agentMessageChunkText(from: message) else {
                    return
                }
                accumulatedText += chunk
                await onPartialText(accumulatedText)
            }
        )

        return accumulatedText
    }

    func cancel() async {
        guard let sessionID else {
            return
        }

        try? await transport.send([
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": [
                "sessionId": sessionID
            ]
        ])
    }

    func close() async {
        transport.close()
    }

    private func ensureSession() async throws -> String {
        if let sessionID {
            return sessionID
        }

        let initializeResult = try await request(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": false,
                        "writeTextFile": false
                    ],
                    "terminal": false
                ],
                "clientInfo": [
                    "name": "tungsten",
                    "title": "Tungsten",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                ]
            ]
        )
        guard initializeResult["protocolVersion"] as? Int == 1 else {
            throw ACPClientError.unsupportedProtocol
        }

        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)

        let sessionResult = try await request(
            method: "session/new",
            params: [
                "cwd": cwd.path,
                "mcpServers": []
            ]
        )
        guard let sessionID = sessionResult["sessionId"] as? String,
              sessionID.isEmpty == false else {
            throw ACPClientError.invalidResponse
        }

        self.sessionID = sessionID
        return sessionID
    }

    private func request(
        method: String,
        params: [String: Any],
        onNotification: (([String: Any]) async -> Void)? = nil
    ) async throws -> [String: Any] {
        let requestID = nextRequestID
        nextRequestID += 1

        try await transport.send([
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ])

        while let message = try await transport.receive() {
            if let responseID = message["id"] as? Int,
               responseID == requestID {
                if let error = message["error"] as? [String: Any] {
                    throw Self.error(from: error)
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw ACPClientError.invalidResponse
                }
                return result
            }

            if message["method"] as? String == "session/update" {
                await onNotification?(message)
            } else if let id = message["id"] as? Int {
                try await transport.send([
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": [
                        "code": -32601,
                        "message": "Method not supported."
                    ]
                ])
            }
        }

        throw ACPClientError.invalidResponse
    }

    private static func error(from object: [String: Any]) -> ACPClientError {
        let message = object["message"] as? String ?? "ACP request failed."
        if object["code"] as? Int == -32000 {
            return .authenticationRequired(message)
        }
        return .processUnavailable(message)
    }

    private static func agentMessageChunkText(from message: [String: Any]) -> String? {
        guard let params = message["params"] as? [String: Any],
              let update = params["update"] as? [String: Any],
              update["sessionUpdate"] as? String == "agent_message_chunk",
              let content = update["content"] as? [String: Any],
              content["type"] as? String == "text" else {
            return nil
        }
        return content["text"] as? String
    }
}

final class ACPStdioTransport: ACPTransport, @unchecked Sendable {
    private let process: Process
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private var outputBuffer = Data()

    init(command: String, arguments: [String]) throws {
        self.process = Process()
        process.executableURL = Self.executableURL(for: command)
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ACPClientError.processUnavailable("Unable to start \(command).")
        }
    }

    func send(_ message: [String: Any]) async throws {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let newline = "\n".data(using: .utf8) else {
            throw ACPClientError.invalidResponse
        }

        try inputPipe.fileHandleForWriting.write(contentsOf: data + newline)
    }

    func receive() async throws -> [String: Any]? {
        while true {
            if let line = nextBufferedLine() {
                return try Self.decodeLine(line)
            }

            let chunk = outputPipe.fileHandleForReading.availableData
            if chunk.isEmpty {
                if process.isRunning == false {
                    return nil
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            } else {
                outputBuffer.append(chunk)
            }
        }
    }

    func close() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func nextBufferedLine() -> Data? {
        guard let newlineIndex = outputBuffer.firstIndex(of: 10) else {
            return nil
        }

        let line = outputBuffer.prefix(upTo: newlineIndex)
        outputBuffer.removeSubrange(...newlineIndex)
        return Data(line)
    }

    private static func decodeLine(_ line: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ACPClientError.invalidResponse
        }
        return object
    }

    static func executableURL(
        for command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if command.contains("/") {
            return URL(fileURLWithPath: command, isDirectory: false)
        }

        let path = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        if command == "codex-acp",
           let zedAdapterURL = newestZedExternalAgentURL(command: command, homeDirectory: homeDirectory) {
            return zedAdapterURL
        }

        return URL(fileURLWithPath: command, isDirectory: false)
    }

    private static func newestZedExternalAgentURL(command: String, homeDirectory: URL) -> URL? {
        let externalAgentsURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Zed", isDirectory: true)
            .appendingPathComponent("external_agents", isDirectory: true)

        let roots = [
            externalAgentsURL.appendingPathComponent("codex", isDirectory: true),
            externalAgentsURL
                .appendingPathComponent("registry", isDirectory: true)
                .appendingPathComponent("codex-acp", isDirectory: true)
        ]
        var candidates = [URL]()

        for root in roots {
            guard let versions = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for versionURL in versions {
                let candidate = versionURL.appendingPathComponent(command, isDirectory: false)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    candidates.append(candidate)
                }
            }
        }

        return candidates.max { lhs, rhs in
            modificationDate(for: lhs) < modificationDate(for: rhs)
        }
    }

    private static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
