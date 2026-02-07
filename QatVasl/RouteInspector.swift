import Foundation

struct RouteContext: Sendable, Equatable {
    let vpnActive: Bool
    let vpnClientName: String?
}

actor RouteInspector {
    private let cacheTTL: TimeInterval
    private var cache: (timestamp: Date, context: RouteContext)?

    init(cacheTTL: TimeInterval = 2) {
        self.cacheTTL = cacheTTL
    }

    func inspect() async -> RouteContext {
        if let cache, Date().timeIntervalSince(cache.timestamp) < cacheTTL {
            return cache.context
        }

        let context = await Task.detached(priority: .utility) {
            Self.detectRouteContext()
        }.value
        cache = (Date(), context)
        return context
    }

    private nonisolated static func detectRouteContext() -> RouteContext {
        let connectedServiceName = detectConnectedVPNServiceName()
        let vpnViaDefaultRoute = detectVPNDefaultRouteActive()
        let vpnActive = connectedServiceName != nil || vpnViaDefaultRoute

        return RouteContext(
            vpnActive: vpnActive,
            vpnClientName: resolveVPNClientName(
                vpnActive: vpnActive,
                connectedServiceName: connectedServiceName
            )
        )
    }

    private nonisolated static func resolveVPNClientName(
        vpnActive: Bool,
        connectedServiceName: String?
    ) -> String? {
        guard vpnActive else {
            return nil
        }

        if let connectedServiceName {
            return connectedServiceName
        }

        if let processName = detectLikelyVPNProcessName() {
            return processName
        }

        return "Unknown VPN client"
    }

    private nonisolated static func detectVPNDefaultRouteActive() -> Bool {
        if
            let defaultIPv4Interface = detectDefaultRouteInterface(arguments: ["-n", "get", "default"]),
            isVPNInterfaceName(defaultIPv4Interface)
        {
            return true
        }

        if
            let defaultIPv6Interface = detectDefaultRouteInterface(arguments: ["-n", "get", "-inet6", "default"]),
            isVPNInterfaceName(defaultIPv6Interface)
        {
            return true
        }

        return false
    }

    private nonisolated static func detectDefaultRouteInterface(arguments: [String]) -> String? {
        guard let output = runCommand("/sbin/route", arguments: arguments) else {
            return nil
        }

        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("interface:") else {
                continue
            }

            let interfaceName = trimmed
                .replacingOccurrences(of: "interface:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !interfaceName.isEmpty {
                return interfaceName
            }
        }

        return nil
    }

    private nonisolated static func isVPNInterfaceName(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("utun") ||
            interfaceName.hasPrefix("tun") ||
            interfaceName.hasPrefix("tap") ||
            interfaceName.hasPrefix("ppp")
    }

    private nonisolated static func detectConnectedVPNServiceName() -> String? {
        guard let output = runCommand("/usr/sbin/scutil", arguments: ["--nc", "list"]) else {
            return nil
        }

        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        for rawLine in lines where rawLine.contains("(Connected)") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if
                let firstQuote = line.firstIndex(of: "\""),
                let secondQuote = line[line.index(after: firstQuote)...].firstIndex(of: "\"")
            {
                let quoted = line[line.index(after: firstQuote)..<secondQuote]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !quoted.isEmpty {
                    return quoted
                }
            }

            let compact = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if !compact.isEmpty {
                return compact
            }
        }

        return nil
    }

    private nonisolated static func detectLikelyVPNProcessName() -> String? {
        guard let output = runCommand("/bin/ps", arguments: ["-axo", "comm"])?.lowercased() else {
            return nil
        }

        let knownClients: [(needle: String, label: String)] = [
            ("happ", "Happ"),
            ("hiddify", "Hiddify"),
            ("openvpn", "OpenVPN"),
            ("wireguard", "WireGuard"),
            ("v2ray", "V2Ray"),
            ("xray", "Xray"),
            ("sing-box", "Sing-box"),
            ("clash", "Clash"),
            ("outline", "Outline"),
            ("protonvpn", "ProtonVPN"),
            ("surfshark", "Surfshark"),
        ]

        for client in knownClients where output.contains(client.needle) {
            return client.label
        }

        return nil
    }

    private nonisolated static func runCommand(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
