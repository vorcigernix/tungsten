import Foundation
import Darwin

struct TorProxyConfiguration: Codable, Equatable {
    var launchesArti: Bool
    var artiExecutablePath: String
    var socksHost: String
    var socksPort: Int

    static let `default` = TorProxyConfiguration(
        launchesArti: true,
        artiExecutablePath: "arti",
        socksHost: "127.0.0.1",
        socksPort: 9150
    )

    var normalizedPort: Int {
        min(max(socksPort, 1), 65535)
    }
}

enum TorNetworkStartupResult: Equatable {
    case running
    case unavailable(String)

    var isRunning: Bool {
        self == .running
    }

    var message: String? {
        guard case .unavailable(let message) = self else {
            return nil
        }
        return message
    }
}

@MainActor
final class TorNetworkService {
    static let shared = TorNetworkService()

    private var process: Process?
    private var runningConfiguration: TorProxyConfiguration?
    private let readinessProbeHost = "check.torproject.org"
    private let readinessProbePort = 443

    private init() {}

    @discardableResult
    func ensureRunning(configuration: TorProxyConfiguration) -> TorNetworkStartupResult {
        let host = configuration.socksHost
        let port = configuration.normalizedPort

        if waitUntilTorProxyCanConnect(host: host, port: port, timeout: 0.25) {
            return .running
        }

        if configuration.launchesArti == false {
            let message: String
            if waitUntilProxyIsListening(host: host, port: port, timeout: 0.15) {
                message = "A SOCKS proxy is listening at \(host):\(port), but it could not complete a Tor connection to \(readinessProbeHost):\(readinessProbePort). Check the proxy and try again."
            } else {
                message = "No SOCKS proxy is listening at \(host):\(port). Start Arti manually or enable Tungsten's Arti launcher in Settings."
            }
            NSLog("Tungsten Tor: %@", message)
            return .unavailable(message)
        }

        if let process, process.isRunning, runningConfiguration == configuration {
            if waitUntilTorProxyCanConnect(host: host, port: port, timeout: 20.0) {
                return .running
            }

            let message = "Arti is running and listening at \(host):\(port), but Tor did not finish bootstrapping a connection to \(readinessProbeHost):\(readinessProbePort). Try again in a few seconds."
            NSLog("Tungsten Tor: %@", message)
            return .unavailable(message)
        }

        stop()

        guard let executableURL = resolveExecutableURL(configuration.artiExecutablePath) else {
            let message = "Arti executable '\(configuration.artiExecutablePath)' was not found. Install Arti or set its full path in Settings."
            NSLog("Tungsten Tor: %@", message)
            return .unavailable(message)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "proxy",
            "-o",
            "proxy.socks_listen = \(port)"
        ]
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard self?.process === terminatedProcess else {
                    return
                }
                self?.process = nil
                self?.runningConfiguration = nil
            }
        }

        do {
            try process.run()
            self.process = process
            runningConfiguration = configuration
            guard waitUntilProxyIsListening(host: host, port: port) else {
                let exitNote = process.isRunning ? "" : " Arti exited before opening the SOCKS port."
                let message = "Arti did not open a SOCKS proxy at \(host):\(port).\(exitNote)"
                NSLog("Tungsten Tor: %@", message)
                stop()
                return .unavailable(message)
            }

            if waitUntilTorProxyCanConnect(host: host, port: port, timeout: 45.0) {
                return .running
            }

            let exitNote = process.isRunning ? "" : " Arti exited before Tor finished bootstrapping."
            let message = "Arti opened a SOCKS proxy at \(host):\(port), but Tor did not complete a connection to \(readinessProbeHost):\(readinessProbePort).\(exitNote)"
            NSLog("Tungsten Tor: %@", message)
            if process.isRunning == false {
                stop()
            }
            return .unavailable(message)
        } catch {
            let message = "Failed to launch Arti at \(executableURL.path): \(error.localizedDescription)"
            NSLog("Tungsten Tor: %@", message)
            return .unavailable(message)
        }
    }

    func stop() {
        guard let process else {
            runningConfiguration = nil
            return
        }

        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        runningConfiguration = nil
    }

    private func resolveExecutableURL(_ path: String) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return nil
        }

        if trimmedPath.contains("/") {
            return FileManager.default.isExecutableFile(atPath: trimmedPath)
                ? URL(fileURLWithPath: trimmedPath)
                : nil
        }

        for candidate in bundledExecutableCandidates(named: trimmedPath) {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let candidateDirectories = pathEntries + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        for directory in candidateDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(trimmedPath).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    private func bundledExecutableCandidates(named executableName: String) -> [URL] {
        var candidates = [URL]()

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent("Arti", isDirectory: true)
                    .appendingPathComponent(executableName, isDirectory: false)
            )
        }

        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("Vendor/Arti/bin", isDirectory: true)
                .appendingPathComponent(executableName, isDirectory: false)
        )

        return candidates
    }

    private func waitUntilProxyIsListening(
        host: String,
        port: Int,
        timeout: TimeInterval = 4.0
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if canOpenTCPConnection(host: host, port: port) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        return false
    }

    private func waitUntilTorProxyCanConnect(
        host: String,
        port: Int,
        timeout: TimeInterval = 30.0
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if canCompleteSOCKS5Connect(
                proxyHost: host,
                proxyPort: port,
                targetHost: readinessProbeHost,
                targetPort: readinessProbePort
            ) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        return false
    }

    private func canOpenTCPConnection(host: String, port: Int) -> Bool {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian

        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return false
        }

        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            return false
        }
        defer {
            close(socketDescriptor)
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func canCompleteSOCKS5Connect(
        proxyHost: String,
        proxyPort: Int,
        targetHost: String,
        targetPort: Int
    ) -> Bool {
        guard let socketDescriptor = openTCPSocket(host: proxyHost, port: proxyPort) else {
            return false
        }
        defer {
            close(socketDescriptor)
        }

        configureSocketTimeouts(socketDescriptor, seconds: 3.0)

        guard sendAll([0x05, 0x01, 0x00], socketDescriptor: socketDescriptor),
              readExactly(2, socketDescriptor: socketDescriptor) == [0x05, 0x00] else {
            return false
        }

        let targetBytes = Array(targetHost.utf8)
        guard targetBytes.count <= 255 else {
            return false
        }

        let portValue = UInt16(targetPort)
        let request = [UInt8(0x05), 0x01, 0x00, 0x03, UInt8(targetBytes.count)]
            + targetBytes
            + [UInt8(portValue >> 8), UInt8(portValue & 0xff)]

        guard sendAll(request, socketDescriptor: socketDescriptor),
              let response = readExactly(4, socketDescriptor: socketDescriptor),
              response[0] == 0x05,
              response[1] == 0x00 else {
            return false
        }

        return true
    }

    private func openTCPSocket(host: String, port: Int) -> Int32? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian

        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            return nil
        }

        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            return nil
        }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }

        if connected == false {
            close(socketDescriptor)
            return nil
        }

        return socketDescriptor
    }

    private func configureSocketTimeouts(_ socketDescriptor: Int32, seconds: TimeInterval) {
        var timeout = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((seconds.truncatingRemainder(dividingBy: 1.0)) * 1_000_000)
        )

        withUnsafePointer(to: &timeout) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { rawPointer in
                setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, rawPointer, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(socketDescriptor, SOL_SOCKET, SO_SNDTIMEO, rawPointer, socklen_t(MemoryLayout<timeval>.size))
            }
        }
    }

    private func sendAll(_ bytes: [UInt8], socketDescriptor: Int32) -> Bool {
        bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return true
            }

            var sent = 0
            while sent < buffer.count {
                let result = send(socketDescriptor, baseAddress.advanced(by: sent), buffer.count - sent, 0)
                guard result > 0 else {
                    return false
                }
                sent += result
            }

            return true
        }
    }

    private func readExactly(_ byteCount: Int, socketDescriptor: Int32) -> [UInt8]? {
        var bytes = Array(repeating: UInt8(0), count: byteCount)
        var received = 0

        while received < byteCount {
            let result = bytes.withUnsafeMutableBytes { buffer in
                recv(socketDescriptor, buffer.baseAddress?.advanced(by: received), byteCount - received, 0)
            }
            guard result > 0 else {
                return nil
            }
            received += result
        }

        return bytes
    }
}
