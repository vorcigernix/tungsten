/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Transforms omnibox input into browser navigation targets.
*/

import Foundation

enum AddressResolver {
    static func navigationTarget(for input: String, searchEngine: SearchEngine = .googleAIMode) -> String? {
        if let target = directNavigationTarget(for: input) {
            return target
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return searchEngine.searchURL(for: trimmed)
    }

    static func directNavigationTarget(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let directURL = directURL(from: trimmed) {
            return directURL
        }

        if let scheme = defaultSchemeForAddress(trimmed) {
            return "\(scheme)://\(trimmed)"
        }

        return nil
    }

    private static let directNavigationSchemes: Set<String> = [
        "http", "https", "file",
        "chrome", "chrome-extension", "chrome-untrusted",
        "devtools", "view-source", "about"
    ]

    private static func directURL(from input: String) -> String? {
        guard
            let components = URLComponents(string: input),
            let scheme = components.scheme?.lowercased(),
            directNavigationSchemes.contains(scheme)
        else {
            return nil
        }

        // Network schemes still require a host so a bare "https://" falls
        // through to a search query. Chrome-internal schemes can be opaque
        // (e.g. "about:blank") so we don't enforce a host for them.
        if scheme == "http" || scheme == "https" {
            guard components.host?.isEmpty == false else {
                return nil
            }
        }

        return input
    }

    private static func defaultSchemeForAddress(_ input: String) -> String? {
        guard input.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }

        let host = hostCandidate(from: input)
        if isLocalHost(host) || isIPAddress(host) {
            return "http"
        }

        if isDomainName(host) {
            return "https"
        }

        return nil
    }

    private static func hostCandidate(from input: String) -> String {
        let terminators = CharacterSet(charactersIn: "/?#")
        let hostAndPort = input.components(separatedBy: terminators).first ?? input

        if hostAndPort.hasPrefix("["),
           let closeBracket = hostAndPort.firstIndex(of: "]") {
            return String(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<closeBracket])
        }

        return hostAndPort.components(separatedBy: ":").first ?? hostAndPort
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host.lowercased() == "localhost"
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let pieces = host.split(separator: ".")
        if pieces.count == 4,
           pieces.allSatisfy({ part in
               guard let value = Int(part), value >= 0, value <= 255 else {
                   return false
               }
               return String(part) == "\(value)"
           }) {
            return true
        }

        return host.contains(":") && host.range(of: #"^[0-9a-fA-F:]+$"#, options: .regularExpression) != nil
    }

    private static func isDomainName(_ host: String) -> Bool {
        guard host.contains(".") else {
            return false
        }

        let labels = host.split(separator: ".")
        guard labels.count >= 2,
              labels.allSatisfy({ $0.isEmpty == false }),
              let topLevel = labels.last,
              topLevel.count >= 2
        else {
            return false
        }

        return labels.allSatisfy { label in
            label.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil
        }
    }
}
