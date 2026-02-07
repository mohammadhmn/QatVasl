import Foundation

enum ConnectivityState: String, Codable, CaseIterable {
    case checking
    case offline
    case degraded
    case usable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.fromStoredRawValue(rawValue) ?? .offline
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func fromStoredRawValue(_ rawValue: String) -> ConnectivityState? {
        if let state = ConnectivityState(rawValue: rawValue) {
            return state
        }

        switch rawValue {
        case "openInternet", "vpnOK", "vpnOrProxyActive":
            return .usable
        case "domesticOnly", "globalLimited":
            return .degraded
        case "offline":
            return .offline
        default:
            return nil
        }
    }

    var shortLabel: String {
        switch self {
        case .checking:
            return "CHECKING"
        case .offline:
            return "OFFLINE"
        case .degraded:
            return "DEGRADED"
        case .usable:
            return "USABLE"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Running live connectivity checks"
        case .offline:
            return "No reliable connectivity"
        case .degraded:
            return "Internet is partially available"
        case .usable:
            return "Internet is currently usable"
        }
    }

    var severity: Int {
        switch self {
        case .checking:
            return -1
        case .offline:
            return 0
        case .degraded:
            return 1
        case .usable:
            return 2
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .offline:
            return "wifi.slash.circle.fill"
        case .degraded:
            return "wifi.exclamationmark"
        case .usable:
            return "checkmark.seal.fill"
        }
    }

    var menuTitle: String {
        "QatVasl \(statusEmoji) \(shortLabel)"
    }

    var compactMenuLabel: String {
        switch self {
        case .checking:
            return "CHK"
        case .offline:
            return "OFF"
        case .degraded:
            return "DEG"
        case .usable:
            return "OK"
        }
    }

    var statusEmoji: String {
        switch self {
        case .checking:
            return "🔵"
        case .offline:
            return "🔴"
        case .degraded:
            return "🟡"
        case .usable:
            return "🟢"
        }
    }
}

enum RouteKind: String, CaseIterable, Identifiable {
    case direct
    case vpn
    case proxy

    var id: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }

    var systemImage: String {
        switch self {
        case .direct:
            return "network"
        case .vpn:
            return "shield.lefthalf.filled"
        case .proxy:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

struct RouteIndicator: Identifiable, Equatable {
    let kind: RouteKind
    let isActive: Bool

    var id: String { kind.id }
}

struct ConnectivityDiagnosis: Equatable {
    let title: String
    let explanation: String
    let actions: [String]

    static let initial = ConnectivityDiagnosis(
        title: "Initial check in progress",
        explanation: "QatVasl is gathering the first probe results.",
        actions: ["Wait for the first check to complete."]
    )
}

struct ConnectivityAssessment: Equatable {
    let state: ConnectivityState
    let diagnosis: ConnectivityDiagnosis
    let routeIndicators: [RouteIndicator]
    let detailLine: String

    static let initial = ConnectivityAssessment(
        state: .checking,
        diagnosis: .initial,
        routeIndicators: [
            RouteIndicator(kind: .direct, isActive: false),
            RouteIndicator(kind: .vpn, isActive: false),
            RouteIndicator(kind: .proxy, isActive: false),
        ],
        detailLine: "Route: checking..."
    )
}

enum RouteSummaryFormatter {
    static func format(vpnActive: Bool, proxyActive: Bool) -> String {
        switch (vpnActive, proxyActive) {
        case (true, true):
            return "Route: VPN + PROXY"
        case (true, false):
            return "Route: VPN"
        case (false, true):
            return "Route: PROXY"
        case (false, false):
            return "Route: DIRECT"
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

enum ProbeKind: String, Codable, CaseIterable, Identifiable {
    case domestic
    case global
    case restrictedDirect
    case restrictedViaProxy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domestic:
            return "Domestic"
        case .global:
            return "Global"
        case .restrictedDirect:
            return "Blocked Service (Direct)"
        case .restrictedViaProxy:
            return "Blocked Service (Proxy)"
        }
    }

    var systemImage: String {
        switch self {
        case .domestic:
            return "house.circle.fill"
        case .global:
            return "globe.europe.africa.fill"
        case .restrictedDirect:
            return "paperplane.circle.fill"
        case .restrictedViaProxy:
            return "lock.shield.fill"
        }
    }
}

struct ProbeResult: Codable, Equatable, Identifiable {
    let kind: ProbeKind
    let target: String
    let ok: Bool
    let statusCode: Int?
    let latencyMs: Int?
    let error: String?

    var id: String {
        kind.rawValue
    }

    var name: String {
        kind.title
    }

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
        kind.systemImage
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
