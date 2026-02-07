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

struct ISPProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var intervalSeconds: Double
    var timeoutSeconds: Double
    var domesticURL: String
    var globalURL: String
    var blockedURL: String
    var proxyEnabled: Bool
    var proxyType: ProxyType
    var proxyHost: String
    var proxyPort: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        intervalSeconds: Double,
        timeoutSeconds: Double,
        domesticURL: String,
        globalURL: String,
        blockedURL: String,
        proxyEnabled: Bool,
        proxyType: ProxyType,
        proxyHost: String,
        proxyPort: Int
    ) {
        self.id = id
        self.name = name
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.domesticURL = domesticURL
        self.globalURL = globalURL
        self.blockedURL = blockedURL
        self.proxyEnabled = proxyEnabled
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
    }

    static func fromCurrentSettings(_ settings: MonitorSettings, name: String, id: String = UUID().uuidString) -> ISPProfile {
        ISPProfile(
            id: id,
            name: name,
            intervalSeconds: settings.intervalSeconds,
            timeoutSeconds: settings.timeoutSeconds,
            domesticURL: settings.domesticURL,
            globalURL: settings.globalURL,
            blockedURL: settings.blockedURL,
            proxyEnabled: settings.proxyEnabled,
            proxyType: settings.proxyType,
            proxyHost: settings.proxyHost,
            proxyPort: settings.proxyPort
        )
    }

    func apply(to settings: inout MonitorSettings) {
        settings.intervalSeconds = intervalSeconds
        settings.timeoutSeconds = timeoutSeconds
        settings.domesticURL = domesticURL
        settings.globalURL = globalURL
        settings.blockedURL = blockedURL
        settings.proxyEnabled = proxyEnabled
        settings.proxyType = proxyType
        settings.proxyHost = proxyHost
        settings.proxyPort = proxyPort
    }
}

struct CriticalServiceConfig: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var url: String
    var enabled: Bool
    var checkDirect: Bool
    var checkProxy: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        url: String,
        enabled: Bool = true,
        checkDirect: Bool = true,
        checkProxy: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.checkDirect = checkDirect
        self.checkProxy = checkProxy
    }

    static var defaults: [CriticalServiceConfig] {
        [
            CriticalServiceConfig(name: "Telegram", url: "https://web.telegram.org/"),
            CriticalServiceConfig(name: "GitHub", url: "https://github.com/"),
            CriticalServiceConfig(name: "Google", url: "https://www.google.com/"),
        ]
    }
}

struct ServiceRouteProbeResult: Equatable {
    let route: RouteKind
    let ok: Bool
    let statusCode: Int?
    let latencyMs: Int?
    let error: String?

    var summary: String {
        if ok {
            if let statusCode, let latencyMs {
                return "✅ \(statusCode) • \(latencyMs) ms"
            }
            return "✅ Reachable"
        }
        if let error, !error.isEmpty {
            return "❌ \(error)"
        }
        return "❌ Failed"
    }
}

struct CriticalServiceResult: Equatable, Identifiable {
    let id: String
    let name: String
    let url: String
    let direct: ServiceRouteProbeResult?
    let proxy: ServiceRouteProbeResult?

    var overallOk: Bool {
        direct?.ok == true || proxy?.ok == true
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
    var ispProfiles: [ISPProfile]
    var activeProfileID: String
    var criticalServices: [CriticalServiceConfig]
    var notificationCooldownMinutes: Double
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var launchAtLogin: Bool

    enum CodingKeys: String, CodingKey {
        case intervalSeconds
        case timeoutSeconds
        case domesticURL
        case globalURL
        case blockedURL
        case proxyEnabled
        case proxyType
        case proxyHost
        case proxyPort
        case notificationsEnabled
        case notifyOnRecovery
        case ispProfiles
        case activeProfileID
        case criticalServices
        case notificationCooldownMinutes
        case quietHoursEnabled
        case quietHoursStart
        case quietHoursEnd
        case launchAtLogin
    }

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
            ispProfiles: [],
            activeProfileID: "",
            criticalServices: CriticalServiceConfig.defaults,
            notificationCooldownMinutes: 3,
            quietHoursEnabled: false,
            quietHoursStart: 0,
            quietHoursEnd: 7,
            launchAtLogin: false
        )
    }

    init(
        intervalSeconds: Double,
        timeoutSeconds: Double,
        domesticURL: String,
        globalURL: String,
        blockedURL: String,
        proxyEnabled: Bool,
        proxyType: ProxyType,
        proxyHost: String,
        proxyPort: Int,
        notificationsEnabled: Bool,
        notifyOnRecovery: Bool,
        ispProfiles: [ISPProfile],
        activeProfileID: String,
        criticalServices: [CriticalServiceConfig],
        notificationCooldownMinutes: Double,
        quietHoursEnabled: Bool,
        quietHoursStart: Int,
        quietHoursEnd: Int,
        launchAtLogin: Bool
    ) {
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.domesticURL = domesticURL
        self.globalURL = globalURL
        self.blockedURL = blockedURL
        self.proxyEnabled = proxyEnabled
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnRecovery = notifyOnRecovery
        self.ispProfiles = ispProfiles
        self.activeProfileID = activeProfileID
        self.criticalServices = criticalServices
        self.notificationCooldownMinutes = notificationCooldownMinutes
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.launchAtLogin = launchAtLogin
        sanitizeProfiles()
        sanitizeCriticalServices()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MonitorSettings.defaults

        intervalSeconds = try container.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        domesticURL = try container.decodeIfPresent(String.self, forKey: .domesticURL) ?? defaults.domesticURL
        globalURL = try container.decodeIfPresent(String.self, forKey: .globalURL) ?? defaults.globalURL
        blockedURL = try container.decodeIfPresent(String.self, forKey: .blockedURL) ?? defaults.blockedURL
        proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? defaults.proxyEnabled
        proxyType = try container.decodeIfPresent(ProxyType.self, forKey: .proxyType) ?? defaults.proxyType
        proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? defaults.proxyHost
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? defaults.proxyPort
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        notifyOnRecovery = try container.decodeIfPresent(Bool.self, forKey: .notifyOnRecovery) ?? defaults.notifyOnRecovery
        ispProfiles = try container.decodeIfPresent([ISPProfile].self, forKey: .ispProfiles) ?? []
        activeProfileID = try container.decodeIfPresent(String.self, forKey: .activeProfileID) ?? ""
        criticalServices = try container.decodeIfPresent([CriticalServiceConfig].self, forKey: .criticalServices) ?? CriticalServiceConfig.defaults
        notificationCooldownMinutes = try container.decodeIfPresent(Double.self, forKey: .notificationCooldownMinutes) ?? defaults.notificationCooldownMinutes
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? defaults.quietHoursEnabled
        quietHoursStart = try container.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? defaults.quietHoursStart
        quietHoursEnd = try container.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? defaults.quietHoursEnd
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin

        sanitizeProfiles()
        sanitizeCriticalServices()
    }

    var normalizedInterval: TimeInterval {
        max(10, min(intervalSeconds, 600))
    }

    var normalizedTimeout: TimeInterval {
        max(2, min(timeoutSeconds, 30))
    }

    var normalizedNotificationCooldown: TimeInterval {
        max(0, min(notificationCooldownMinutes, 120)) * 60
    }

    var normalizedQuietHoursStart: Int {
        max(0, min(quietHoursStart, 23))
    }

    var normalizedQuietHoursEnd: Int {
        max(0, min(quietHoursEnd, 23))
    }

    mutating func applyPreset(_ preset: SettingsPreset) {
        switch preset {
        case .balancedIran:
            intervalSeconds = 30
            timeoutSeconds = 7
            notificationsEnabled = true
            notifyOnRecovery = true
            notificationCooldownMinutes = 3
            quietHoursEnabled = false
        case .rapidFailover:
            intervalSeconds = 12
            timeoutSeconds = 4
            notificationsEnabled = true
            notifyOnRecovery = true
            notificationCooldownMinutes = 1
            quietHoursEnabled = false
        case .stableQuiet:
            intervalSeconds = 60
            timeoutSeconds = 8
            notificationsEnabled = true
            notifyOnRecovery = false
            notificationCooldownMinutes = 10
            quietHoursEnabled = true
            quietHoursStart = 0
            quietHoursEnd = 7
        }
    }

    var activeProfile: ISPProfile? {
        ispProfiles.first(where: { $0.id == activeProfileID })
    }

    mutating func selectProfile(id: String) {
        guard let profile = ispProfiles.first(where: { $0.id == id }) else {
            return
        }
        activeProfileID = profile.id
        profile.apply(to: &self)
    }

    mutating func syncActiveProfileFromCurrentValues() {
        sanitizeProfiles()
        guard let index = ispProfiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }

        ispProfiles[index].intervalSeconds = intervalSeconds
        ispProfiles[index].timeoutSeconds = timeoutSeconds
        ispProfiles[index].domesticURL = domesticURL
        ispProfiles[index].globalURL = globalURL
        ispProfiles[index].blockedURL = blockedURL
        ispProfiles[index].proxyEnabled = proxyEnabled
        ispProfiles[index].proxyType = proxyType
        ispProfiles[index].proxyHost = proxyHost
        ispProfiles[index].proxyPort = proxyPort
    }

    mutating func addProfile(named name: String) {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Profile \(ispProfiles.count + 1)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let profile = ISPProfile.fromCurrentSettings(self, name: newName)
        ispProfiles.append(profile)
        activeProfileID = profile.id
    }

    mutating func renameProfile(id: String, name: String) {
        guard let index = ispProfiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        ispProfiles[index].name = trimmed.isEmpty ? "Profile" : trimmed
    }

    mutating func removeProfile(id: String) {
        guard ispProfiles.count > 1 else {
            return
        }
        ispProfiles.removeAll { $0.id == id }
        sanitizeProfiles()
    }

    mutating func sanitizeProfiles() {
        if ispProfiles.isEmpty {
            let primary = ISPProfile.fromCurrentSettings(self, name: "Primary ISP")
            let backup = ISPProfile.fromCurrentSettings(self, name: "Backup ISP")
            let mobile = ISPProfile.fromCurrentSettings(self, name: "Mobile ISP")
            ispProfiles = [primary, backup, mobile]
            activeProfileID = primary.id
            primary.apply(to: &self)
            return
        }

        if activeProfileID.isEmpty || !ispProfiles.contains(where: { $0.id == activeProfileID }) {
            if let first = ispProfiles.first {
                activeProfileID = first.id
                first.apply(to: &self)
            }
        }
    }

    mutating func sanitizeCriticalServices() {
        if criticalServices.isEmpty {
            criticalServices = CriticalServiceConfig.defaults
            return
        }

        var seen = Set<String>()
        criticalServices = criticalServices.filter { service in
            if seen.contains(service.id) {
                return false
            }
            seen.insert(service.id)
            return true
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

struct HealthSample: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let state: ConnectivityState
    let averageLatencyMs: Int?
    let routeLabel: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        state: ConnectivityState,
        averageLatencyMs: Int?,
        routeLabel: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.averageLatencyMs = averageLatencyMs
        self.routeLabel = routeLabel
    }
}

struct TimelineSummary: Equatable {
    let uptimePercent: Int
    let dropCount: Int
    let averageLatencyMs: Int?
    let meanRecoverySeconds: Int?
    let sampleCount: Int

    static let empty = TimelineSummary(
        uptimePercent: 0,
        dropCount: 0,
        averageLatencyMs: nil,
        meanRecoverySeconds: nil,
        sampleCount: 0
    )
}
