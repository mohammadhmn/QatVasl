import Foundation

enum ConnectivityState: String, Codable, CaseIterable {
    case checking
    case offline
    case degraded
    case vpnIssue
    case usable

    var shortLabel: String {
        switch self {
        case .checking:
            return "CHECKING"
        case .offline:
            return "OFFLINE"
        case .degraded:
            return "DEGRADED"
        case .vpnIssue:
            return "VPN ISSUE"
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
        case .vpnIssue:
            return "VPN/TUN is up but Blocked Service route is failing"
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
        case .vpnIssue:
            return 0
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
        case .vpnIssue:
            return "shield.slash.fill"
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
        case .vpnIssue:
            return "VPN!"
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
        case .vpnIssue:
            return "🟠"
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
    var domesticExtraURLs: [String]
    var globalURL: String
    var globalExtraURLs: [String]
    var blockedURL: String
    var blockedExtraURLs: [String]
    var proxyEnabled: Bool
    var proxyType: ProxyType
    var proxyHost: String
    var proxyPort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case intervalSeconds
        case timeoutSeconds
        case domesticURL
        case domesticExtraURLs
        case globalURL
        case globalExtraURLs
        case blockedURL
        case blockedExtraURLs
        case proxyEnabled
        case proxyType
        case proxyHost
        case proxyPort
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        intervalSeconds: Double,
        timeoutSeconds: Double,
        domesticURL: String,
        domesticExtraURLs: [String] = [],
        globalURL: String,
        globalExtraURLs: [String] = [],
        blockedURL: String,
        blockedExtraURLs: [String] = [],
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
        self.domesticExtraURLs = domesticExtraURLs
        self.globalURL = globalURL
        self.globalExtraURLs = globalExtraURLs
        self.blockedURL = blockedURL
        self.blockedExtraURLs = blockedExtraURLs
        self.proxyEnabled = proxyEnabled
        self.proxyType = proxyType
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "ISP"
        intervalSeconds = try container.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? 30
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 7
        domesticURL = try container.decodeIfPresent(String.self, forKey: .domesticURL) ?? MonitorSettings.defaults.domesticURL
        domesticExtraURLs = try container.decodeIfPresent([String].self, forKey: .domesticExtraURLs) ?? []
        globalURL = try container.decodeIfPresent(String.self, forKey: .globalURL) ?? MonitorSettings.defaults.globalURL
        globalExtraURLs = try container.decodeIfPresent([String].self, forKey: .globalExtraURLs) ?? []
        blockedURL = try container.decodeIfPresent(String.self, forKey: .blockedURL) ?? MonitorSettings.defaults.blockedURL
        blockedExtraURLs = try container.decodeIfPresent([String].self, forKey: .blockedExtraURLs) ?? []
        proxyEnabled = try container.decodeIfPresent(Bool.self, forKey: .proxyEnabled) ?? true
        proxyType = try container.decodeIfPresent(ProxyType.self, forKey: .proxyType) ?? .socks5
        proxyHost = try container.decodeIfPresent(String.self, forKey: .proxyHost) ?? "127.0.0.1"
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? 10808
    }

    static func fromCurrentSettings(_ settings: MonitorSettings, name: String, id: String = UUID().uuidString) -> ISPProfile {
        ISPProfile(
            id: id,
            name: name,
            intervalSeconds: settings.intervalSeconds,
            timeoutSeconds: settings.timeoutSeconds,
            domesticURL: settings.domesticURL,
            domesticExtraURLs: settings.domesticExtraURLs,
            globalURL: settings.globalURL,
            globalExtraURLs: settings.globalExtraURLs,
            blockedURL: settings.blockedURL,
            blockedExtraURLs: settings.blockedExtraURLs,
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
        settings.domesticExtraURLs = domesticExtraURLs
        settings.globalURL = globalURL
        settings.globalExtraURLs = globalExtraURLs
        settings.blockedURL = blockedURL
        settings.blockedExtraURLs = blockedExtraURLs
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
            CriticalServiceConfig(name: "Stack Overflow", url: "https://stackoverflow.com/"),
            CriticalServiceConfig(name: "NPM Registry", url: "https://registry.npmjs.org/"),
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
    var domesticExtraURLs: [String]
    var globalURL: String
    var globalExtraURLs: [String]
    var blockedURL: String
    var blockedExtraURLs: [String]
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
    var autoDetectISPOnLaunch: Bool
    var iranPulseEnabled: Bool
    var iranPulseIntervalMinutes: Double
    var iranPulseVanillappEnabled: Bool
    var iranPulseOoniEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case intervalSeconds
        case timeoutSeconds
        case domesticURL
        case domesticExtraURLs
        case globalURL
        case globalExtraURLs
        case blockedURL
        case blockedExtraURLs
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
        case autoDetectISPOnLaunch
        case iranPulseEnabled
        case iranPulseIntervalMinutes
        case iranPulseVanillappEnabled
        case iranPulseOoniEnabled
    }

    static var defaults: MonitorSettings {
        MonitorSettings(
            intervalSeconds: 30,
            timeoutSeconds: 7,
            domesticURL: "https://www.aparat.com/",
            domesticExtraURLs: [],
            globalURL: "https://www.google.com/generate_204",
            globalExtraURLs: [],
            blockedURL: "https://web.telegram.org/",
            blockedExtraURLs: [],
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
            launchAtLogin: false,
            autoDetectISPOnLaunch: true,
            iranPulseEnabled: true,
            iranPulseIntervalMinutes: 5,
            iranPulseVanillappEnabled: true,
            iranPulseOoniEnabled: true
        )
    }

    init(
        intervalSeconds: Double,
        timeoutSeconds: Double,
        domesticURL: String,
        domesticExtraURLs: [String] = [],
        globalURL: String,
        globalExtraURLs: [String] = [],
        blockedURL: String,
        blockedExtraURLs: [String] = [],
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
        launchAtLogin: Bool,
        autoDetectISPOnLaunch: Bool,
        iranPulseEnabled: Bool,
        iranPulseIntervalMinutes: Double,
        iranPulseVanillappEnabled: Bool,
        iranPulseOoniEnabled: Bool
    ) {
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.domesticURL = domesticURL
        self.domesticExtraURLs = domesticExtraURLs
        self.globalURL = globalURL
        self.globalExtraURLs = globalExtraURLs
        self.blockedURL = blockedURL
        self.blockedExtraURLs = blockedExtraURLs
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
        self.autoDetectISPOnLaunch = autoDetectISPOnLaunch
        self.iranPulseEnabled = iranPulseEnabled
        self.iranPulseIntervalMinutes = iranPulseIntervalMinutes
        self.iranPulseVanillappEnabled = iranPulseVanillappEnabled
        self.iranPulseOoniEnabled = iranPulseOoniEnabled
        sanitizeProfiles()
        sanitizeCriticalServices()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MonitorSettings.defaults

        intervalSeconds = try container.decodeIfPresent(Double.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        domesticURL = try container.decodeIfPresent(String.self, forKey: .domesticURL) ?? defaults.domesticURL
        domesticExtraURLs = try container.decodeIfPresent([String].self, forKey: .domesticExtraURLs) ?? defaults.domesticExtraURLs
        globalURL = try container.decodeIfPresent(String.self, forKey: .globalURL) ?? defaults.globalURL
        globalExtraURLs = try container.decodeIfPresent([String].self, forKey: .globalExtraURLs) ?? defaults.globalExtraURLs
        blockedURL = try container.decodeIfPresent(String.self, forKey: .blockedURL) ?? defaults.blockedURL
        blockedExtraURLs = try container.decodeIfPresent([String].self, forKey: .blockedExtraURLs) ?? defaults.blockedExtraURLs
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
        autoDetectISPOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoDetectISPOnLaunch) ?? defaults.autoDetectISPOnLaunch
        iranPulseEnabled = try container.decodeIfPresent(Bool.self, forKey: .iranPulseEnabled) ?? defaults.iranPulseEnabled
        iranPulseIntervalMinutes = try container.decodeIfPresent(Double.self, forKey: .iranPulseIntervalMinutes) ?? defaults.iranPulseIntervalMinutes
        iranPulseVanillappEnabled = try container.decodeIfPresent(Bool.self, forKey: .iranPulseVanillappEnabled) ?? defaults.iranPulseVanillappEnabled
        iranPulseOoniEnabled = try container.decodeIfPresent(Bool.self, forKey: .iranPulseOoniEnabled) ?? defaults.iranPulseOoniEnabled

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

    var normalizedIranPulseInterval: TimeInterval {
        max(120, min(iranPulseIntervalMinutes * 60, 3600))
    }

    var domesticProbeTargets: [String] {
        mergedProbeTargets(primary: domesticURL, extras: domesticExtraURLs)
    }

    var globalProbeTargets: [String] {
        mergedProbeTargets(primary: globalURL, extras: globalExtraURLs)
    }

    var blockedProbeTargets: [String] {
        mergedProbeTargets(primary: blockedURL, extras: blockedExtraURLs)
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
        ispProfiles[index].domesticExtraURLs = domesticExtraURLs
        ispProfiles[index].globalURL = globalURL
        ispProfiles[index].globalExtraURLs = globalExtraURLs
        ispProfiles[index].blockedURL = blockedURL
        ispProfiles[index].blockedExtraURLs = blockedExtraURLs
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

    private func mergedProbeTargets(primary: String, extras: [String]) -> [String] {
        var seen = Set<String>()
        let ordered = [primary] + extras
        var results: [String] = []
        results.reserveCapacity(ordered.count)

        for raw in ordered {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            results.append(trimmed)
        }

        return results
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

struct MonitorPerformanceSummary: Equatable {
    let lastCheckDurationMs: Int?
    let averageCheckDurationMs: Int?
    let lastRouteInspectMs: Int?
    let lastSnapshotProbeMs: Int?
    let lastProxyEndpointMs: Int?
    let lastCriticalServicesRefreshMs: Int?
    let criticalServicesRefreshCount: Int
    let persistenceFlushCount: Int

    static let empty = MonitorPerformanceSummary(
        lastCheckDurationMs: nil,
        averageCheckDurationMs: nil,
        lastRouteInspectMs: nil,
        lastSnapshotProbeMs: nil,
        lastProxyEndpointMs: nil,
        lastCriticalServicesRefreshMs: nil,
        criticalServicesRefreshCount: 0,
        persistenceFlushCount: 0
    )
}

enum IranPulseSource: String, Codable, CaseIterable, Identifiable {
    case vanillapp
    case ooni

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vanillapp:
            return "Vanillapp Radar"
        case .ooni:
            return "OONI"
        }
    }
}

enum IranPulseSeverity: String, Codable, Equatable {
    case normal
    case degraded
    case severe
    case unknown

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .degraded:
            return "Degraded"
        case .severe:
            return "Severe"
        case .unknown:
            return "Unknown"
        }
    }

    var compactLabel: String {
        switch self {
        case .normal:
            return "OK"
        case .degraded:
            return "DEG"
        case .severe:
            return "SEV"
        case .unknown:
            return "UNK"
        }
    }
}

struct IranPulseProviderSnapshot: Codable, Equatable, Identifiable {
    let source: IranPulseSource
    let score: Int?
    let severity: IranPulseSeverity
    let confidence: Double
    let capturedAt: Date?
    let stale: Bool
    let summary: String
    let details: [String: String]
    let error: String?

    var id: String { source.rawValue }
}

struct IranPulseSnapshot: Codable, Equatable {
    let score: Int?
    let severity: IranPulseSeverity
    let confidence: Double
    let summary: String
    let providers: [IranPulseProviderSnapshot]
    let lastUpdated: Date

    var compactLabel: String {
        if let score {
            return "\(severity.compactLabel) \(score)"
        }
        return severity.compactLabel
    }

    static func initial(now: Date = Date()) -> IranPulseSnapshot {
        IranPulseSnapshot(
            score: nil,
            severity: .unknown,
            confidence: 0,
            summary: "Waiting for first national pulse check.",
            providers: [],
            lastUpdated: now
        )
    }

    static func disabled(now: Date = Date()) -> IranPulseSnapshot {
        IranPulseSnapshot(
            score: nil,
            severity: .unknown,
            confidence: 0,
            summary: "National pulse monitoring is disabled.",
            providers: [],
            lastUpdated: now
        )
    }

    static func noProviders(now: Date = Date()) -> IranPulseSnapshot {
        IranPulseSnapshot(
            score: nil,
            severity: .unknown,
            confidence: 0,
            summary: "No Iran pulse providers are enabled.",
            providers: [],
            lastUpdated: now
        )
    }
}

enum LocalVsNationalCorrelationKind: String, Equatable {
    case likelyLocalIssue
    case likelyNationalDisruption
    case mixedSignals
    case stable
    case inconclusive
}

struct LocalVsNationalCorrelationHint: Equatable {
    let kind: LocalVsNationalCorrelationKind
    let title: String
    let explanation: String
    let recommendedAction: String
}

enum LocalVsNationalCorrelationEvaluator {
    private static let minimumPulseConfidence = 0.45

    static func evaluate(
        localState: ConnectivityState,
        pulse: IranPulseSnapshot,
        pulseEnabled: Bool
    ) -> LocalVsNationalCorrelationHint {
        if localState == .checking {
            return LocalVsNationalCorrelationHint(
                kind: .inconclusive,
                title: "Correlation pending",
                explanation: "Local connectivity checks are still in progress.",
                recommendedAction: "Wait for the next check cycle."
            )
        }

        if !pulseEnabled {
            return LocalVsNationalCorrelationHint(
                kind: .inconclusive,
                title: "National signal unavailable",
                explanation: "Iran Pulse monitoring is currently disabled, so correlation cannot be estimated.",
                recommendedAction: "Enable Iran Pulse in Settings for local-vs-national hints."
            )
        }

        let hasPulseData = pulse.score != nil && !pulse.providers.isEmpty
        if !hasPulseData || pulse.confidence < minimumPulseConfidence || pulse.severity == .unknown {
            return LocalVsNationalCorrelationHint(
                kind: .inconclusive,
                title: "Correlation low confidence",
                explanation: "National pulse data is missing or low-confidence right now.",
                recommendedAction: "Use local probes first and re-check when pulse confidence improves."
            )
        }

        let pulseScore = pulse.score ?? 0
        let nationalHealthy = pulse.severity == .normal && pulseScore >= 80
        let nationalDisrupted = pulse.severity == .severe || (pulse.severity == .degraded && pulseScore < 65)
        let localIssue = localState == .offline || localState == .vpnIssue || localState == .degraded

        if localIssue && nationalDisrupted {
            return LocalVsNationalCorrelationHint(
                kind: .likelyNationalDisruption,
                title: "Likely country-wide disruption",
                explanation: "Local connectivity is degraded while Iran Pulse also reports broad disruption.",
                recommendedAction: "Avoid local over-tuning; wait or switch route/provider only for urgent tasks."
            )
        }

        if localIssue && nationalHealthy {
            return LocalVsNationalCorrelationHint(
                kind: .likelyLocalIssue,
                title: "Likely local route issue",
                explanation: "Your local checks fail, but Iran Pulse indicates normal country-wide conditions.",
                recommendedAction: "Focus on ISP/VPN/proxy rotation and local network troubleshooting."
            )
        }

        if !localIssue && nationalDisrupted {
            return LocalVsNationalCorrelationHint(
                kind: .mixedSignals,
                title: "National disruption, local route still works",
                explanation: "Country-wide conditions are degraded, but your current local route remains usable.",
                recommendedAction: "Keep current route stable and avoid unnecessary reconnects."
            )
        }

        if !localIssue && nationalHealthy {
            return LocalVsNationalCorrelationHint(
                kind: .stable,
                title: "Local and national signals are healthy",
                explanation: "Both local probes and Iran Pulse indicate stable connectivity.",
                recommendedAction: "Continue normal operation and monitor for transitions."
            )
        }

        return LocalVsNationalCorrelationHint(
            kind: .mixedSignals,
            title: "Mixed local/national signals",
            explanation: "Signals are partially aligned but not strong enough for a strict local-vs-national verdict.",
            recommendedAction: "Use service-level checks and recent transitions before changing setup."
        )
    }
}
