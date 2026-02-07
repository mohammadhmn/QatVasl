import Foundation

enum ConnectivityState: String, Codable, CaseIterable {
    case offline
    case domesticOnly
    case globalLimited
    case vpnOK
    case tunActive
    case openInternet

    var shortLabel: String {
        switch self {
        case .offline:
            return "OFFLINE"
        case .domesticOnly:
            return "IR ONLY"
        case .globalLimited:
            return "LIMITED"
        case .vpnOK:
            return "VPN OK"
        case .tunActive:
            return "TUN ON"
        case .openInternet:
            return "OPEN"
        }
    }

    var detail: String {
        switch self {
        case .offline:
            return "No reliable connectivity"
        case .domesticOnly:
            return "Domestic routes work, global internet fails"
        case .globalLimited:
            return "Global web works, blocked services fail"
        case .vpnOK:
            return "Blocked targets reachable through proxy"
        case .tunActive:
            return "Traffic routed by system tunnel/proxy"
        case .openInternet:
            return "Blocked targets reachable without proxy"
        }
    }

    var severity: Int {
        switch self {
        case .offline:
            return 0
        case .domesticOnly:
            return 1
        case .globalLimited:
            return 2
        case .vpnOK:
            return 3
        case .tunActive:
            return 3
        case .openInternet:
            return 4
        }
    }

    var colorName: String {
        switch self {
        case .offline:
            return "red"
        case .domesticOnly:
            return "orange"
        case .globalLimited:
            return "yellow"
        case .vpnOK, .openInternet:
            return "green"
        case .tunActive:
            return "yellow"
        }
    }

    var systemImage: String {
        switch self {
        case .offline:
            return "wifi.slash.circle.fill"
        case .domesticOnly:
            return "wifi.exclamationmark.circle.fill"
        case .globalLimited:
            return "network"
        case .vpnOK:
            return "lock.shield.fill"
        case .tunActive:
            return "lock.fill"
        case .openInternet:
            return "globe.americas.fill"
        }
    }

    var menuTitle: String {
        "QatVasl \(statusEmoji) \(shortLabel)"
    }

    var compactMenuLabel: String {
        switch self {
        case .offline:
            return "OFF"
        case .domesticOnly:
            return "IR"
        case .globalLimited:
            return "LMT"
        case .vpnOK:
            return "VPN"
        case .tunActive:
            return "TUN"
        case .openInternet:
            return "OPEN"
        }
    }

    var statusEmoji: String {
        switch self {
        case .offline:
            return "🔴"
        case .domesticOnly:
            return "🟠"
        case .globalLimited:
            return "🟡"
        case .tunActive:
            return "🔵"
        case .vpnOK, .openInternet:
            return "🟢"
        }
    }

    var suggestedAction: String {
        switch self {
        case .offline:
            return "Switch ISP first, then refresh. If unchanged, rotate VPN config."
        case .domesticOnly:
            return "Domestic routes are up. Keep ISP and rotate VPN config."
        case .globalLimited:
            return "Global web works. VPN route likely blocked; rotate tunnel/profile."
        case .vpnOK:
            return "You are connected through VPN. Keep this config and monitor stability."
        case .tunActive:
            return "Direct-path verdict is paused. Disable TUN/proxy to test raw internet directly."
        case .openInternet:
            return "Direct access is currently open. VPN is optional unless needed."
        }
    }
}

enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case socks5
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socks5:
            return "SOCKS5"
        case .http:
            return "HTTP"
        }
    }
}

struct MonitorSettings: Codable, Equatable {
    var intervalSeconds: Double
    var timeoutSeconds: Double
    var domesticURL: String
    var globalURL: String
    var blockedURL: String
    var proxyEnabled: Bool
    var proxyType: ProxyType
    var proxyHost: String
    var proxyPort: Int
    var notificationsEnabled: Bool
    var notifyOnRecovery: Bool
    var launchAtLogin: Bool

    static var defaults: MonitorSettings {
        MonitorSettings(
            intervalSeconds: 30,
            timeoutSeconds: 7,
            domesticURL: "https://www.aparat.com/",
            globalURL: "https://www.google.com/generate_204",
            blockedURL: "https://web.telegram.org/",
            proxyEnabled: true,
            proxyType: .socks5,
            proxyHost: "127.0.0.1",
            proxyPort: 10808,
            notificationsEnabled: true,
            notifyOnRecovery: true,
            launchAtLogin: false
        )
    }

    var normalizedInterval: TimeInterval {
        max(10, min(intervalSeconds, 600))
    }

    var normalizedTimeout: TimeInterval {
        max(2, min(timeoutSeconds, 30))
    }

    mutating func applyPreset(_ preset: SettingsPreset) {
        switch preset {
        case .balancedIran:
            intervalSeconds = 30
            timeoutSeconds = 7
            notificationsEnabled = true
            notifyOnRecovery = true
        case .rapidFailover:
            intervalSeconds = 12
            timeoutSeconds = 4
            notificationsEnabled = true
            notifyOnRecovery = true
        case .stableQuiet:
            intervalSeconds = 60
            timeoutSeconds = 8
            notificationsEnabled = true
            notifyOnRecovery = false
        }
    }
}

enum SettingsPreset: String, CaseIterable, Identifiable {
    case balancedIran
    case rapidFailover
    case stableQuiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balancedIran:
            return "Balanced (Iran)"
        case .rapidFailover:
            return "Rapid Failover"
        case .stableQuiet:
            return "Stable + Quiet"
        }
    }

    var subtitle: String {
        switch self {
        case .balancedIran:
            return "30s checks, practical daily default."
        case .rapidFailover:
            return "Fast detection for unstable sessions."
        case .stableQuiet:
            return "Lower noise, less frequent checks."
        }
    }
}

struct ProbeResult: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let target: String
    let ok: Bool
    let statusCode: Int?
    let latencyMs: Int?
    let error: String?

    var summary: String {
        if ok {
            if let statusCode, let latencyMs {
                return "✅ \(statusCode) (\(latencyMs) ms)"
            }
            return "✅ Reachable"
        }

        if let statusCode, let latencyMs {
            return "⚠️ \(statusCode) (\(latencyMs) ms)"
        }

        if let error, !error.isEmpty {
            return "❌ \(error)"
        }

        return "❌ Failed"
    }

    var systemImage: String {
        switch id {
        case "domestic":
            return "house.circle.fill"
        case "global":
            return "globe.europe.africa.fill"
        case "blocked_direct":
            return "paperplane.circle.fill"
        case "blocked_proxy":
            return "lock.shield.fill"
        default:
            return "dot.circle"
        }
    }
}

struct ProbeSnapshot: Codable, Equatable {
    let timestamp: Date
    let domestic: ProbeResult
    let global: ProbeResult
    let blockedDirect: ProbeResult
    let blockedProxy: ProbeResult

    var allResults: [ProbeResult] {
        [domestic, global, blockedDirect, blockedProxy]
    }
}

struct StateTransition: Codable, Equatable, Identifiable {
    let id: UUID
    let from: ConnectivityState
    let to: ConnectivityState
    let timestamp: Date

    init(from: ConnectivityState, to: ConnectivityState, timestamp: Date = Date()) {
        self.id = UUID()
        self.from = from
        self.to = to
        self.timestamp = timestamp
    }

    var label: String {
        "\(from.shortLabel) → \(to.shortLabel)"
    }
}
