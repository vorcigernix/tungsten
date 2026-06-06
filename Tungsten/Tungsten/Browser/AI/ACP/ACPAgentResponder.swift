import Foundation

protocol ACPAgentAnsweringClient: Sendable {
    func answer(
        _ prompt: String,
        onPartialText: @escaping @Sendable (String) async -> Void
    ) async throws -> String

    func cancel() async
    func close() async
}

extension ACPClient: ACPAgentAnsweringClient {}

final class ACPAgentResponder: LocalAIAnswering, @unchecked Sendable {
    let providerName: String
    let configuration: ACPProviderConfiguration
    private let clientSession: ACPAgentResponderSession

    init(
        providerName: String,
        configuration: ACPProviderConfiguration,
        clientFactory: @escaping @Sendable (ACPProviderConfiguration) throws -> any ACPAgentAnsweringClient = {
            try ACPAgentResponder.defaultClient(configuration: $0)
        }
    ) {
        self.providerName = providerName
        self.configuration = configuration
        clientSession = ACPAgentResponderSession(configuration: configuration, clientFactory: clientFactory)
    }

    deinit {
        Task { [clientSession] in
            await clientSession.close()
        }
    }

    static func codex(configuration: ACPProviderConfiguration) -> ACPAgentResponder {
        ACPAgentResponder(providerName: "Codex via ACP", configuration: configuration)
    }

    static func claude(configuration: ACPProviderConfiguration) -> ACPAgentResponder {
        ACPAgentResponder(providerName: "Claude via ACP", configuration: configuration)
    }

    func answer(_ question: String, pageContext: PageContentContext?) async -> LocalAIResult {
        await answer(question, pageContext: pageContext, onPartialAnswer: { _ in })
    }

    func answer(
        _ question: String,
        pageContext: PageContentContext?,
        onPartialAnswer: @escaping @Sendable (String) async -> Void
    ) async -> LocalAIResult {
        do {
            let prompt = Self.prompt(question: question, pageContext: pageContext)
            let answer = try await clientSession.answer(prompt, onPartialText: onPartialAnswer)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard answer.isEmpty == false else {
                return .unavailable("\(providerName) returned an empty answer.")
            }

            return .answered(answer)
        } catch ACPClientError.authenticationRequired {
            return .unavailable("\(providerName) requires authentication. Sign in with the provider CLI and try again.")
        } catch {
            return .unavailable("\(providerName) is unavailable. Check the command in Settings.")
        }
    }

    func cancel() async {
        await clientSession.cancel()
    }

    func close() async {
        await clientSession.close()
    }

    private static func prompt(question: String, pageContext: PageContentContext?) -> String {
        [
            LocalAIPrompts.instructions(hasPageContext: pageContext != nil),
            "",
            LocalAIPrompts.prompt(question: question, pageContext: pageContext)
        ].joined(separator: "\n")
    }

    private static func defaultClient(
        configuration: ACPProviderConfiguration
    ) throws -> any ACPAgentAnsweringClient {
        let launchConfiguration = launchConfiguration(for: configuration)
        let command = launchConfiguration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.isEmpty == false else {
            throw ACPClientError.processUnavailable("ACP command is empty.")
        }

        let transport = try ACPStdioTransport(command: command, arguments: launchConfiguration.arguments)
        return ACPClient(transport: transport)
    }

    static func launchConfiguration(
        for configuration: ACPProviderConfiguration,
        disabledMCPServerNames: [String]? = nil,
        disabledPluginNames: [String]? = nil
    ) -> ACPProviderConfiguration {
        let command = configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(fileURLWithPath: command).lastPathComponent == "codex-acp" else {
            return configuration
        }

        var launchConfiguration = configuration
        var arguments = launchConfiguration.arguments
        appendCodexConfigOverride("mcp_oauth_credentials_store=\"file\"", to: &arguments)

        let mcpServerNames = disabledMCPServerNames ?? configuredTableNames(rootKey: "mcp_servers")
        for name in mcpServerNames {
            appendCodexConfigOverride("mcp_servers.\(tomlKey(name)).enabled=false", to: &arguments)
        }

        let pluginNames = disabledPluginNames ?? configuredTableNames(rootKey: "plugins")
        for name in pluginNames {
            appendCodexConfigOverride("plugins.\(tomlKey(name)).enabled=false", to: &arguments)
        }

        launchConfiguration.arguments = arguments
        return launchConfiguration
    }

    private static func appendCodexConfigOverride(_ override: String, to arguments: inout [String]) {
        guard arguments.contains(override) == false else {
            return
        }

        arguments.append("-c")
        arguments.append(override)
    }

    private static func configuredTableNames(rootKey: String) -> [String] {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }

        var names = Set<String>()
        for line in contents.components(separatedBy: .newlines) {
            guard let name = tableName(in: line, rootKey: rootKey) else {
                continue
            }
            names.insert(name)
        }
        return names.sorted()
    }

    private static func tableName(in line: String, rootKey: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "[\(rootKey)."
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("]") else {
            return nil
        }

        let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let end = trimmed.index(before: trimmed.endIndex)
        let tablePath = trimmed[start..<end]

        if tablePath.first == "\"" {
            var escaped = false
            var name = ""
            for character in tablePath.dropFirst() {
                if escaped {
                    name.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    return name.isEmpty ? nil : name
                } else {
                    name.append(character)
                }
            }
            return nil
        }

        let name = tablePath.split(separator: ".").first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    private static func tomlKey(_ value: String) -> String {
        let bareKeyPattern = #"^[A-Za-z0-9_-]+$"#
        if value.range(of: bareKeyPattern, options: .regularExpression) != nil {
            return value
        }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private actor ACPAgentResponderSession {
    private let configuration: ACPProviderConfiguration
    private let clientFactory: @Sendable (ACPProviderConfiguration) throws -> any ACPAgentAnsweringClient
    private var client: (any ACPAgentAnsweringClient)?

    init(
        configuration: ACPProviderConfiguration,
        clientFactory: @escaping @Sendable (ACPProviderConfiguration) throws -> any ACPAgentAnsweringClient
    ) {
        self.configuration = configuration
        self.clientFactory = clientFactory
    }

    func answer(
        _ prompt: String,
        onPartialText: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let client = try resolvedClient()
        do {
            return try await client.answer(prompt, onPartialText: onPartialText)
        } catch {
            self.client = nil
            await client.close()
            throw error
        }
    }

    func cancel() async {
        guard let client else {
            return
        }

        self.client = nil
        await client.cancel()
        await client.close()
    }

    func close() async {
        guard let client else {
            return
        }

        self.client = nil
        await client.close()
    }

    private func resolvedClient() throws -> any ACPAgentAnsweringClient {
        if let client {
            return client
        }

        let client = try clientFactory(configuration)
        self.client = client
        return client
    }
}
