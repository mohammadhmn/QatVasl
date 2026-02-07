import CFNetwork
import Combine
import Darwin
import Foundation
import UserNotifications

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var currentState: ConnectivityState
    @Published private(set) var lastSnapshot: ProbeSnapshot?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var latestError: String?
    @Published private(set) var transitionHistory: [StateTransition]
    @Published private(set) var tunnelDetected = false
    @Published private(set) var systemProxyDetected = false
    @Published private(set) var vpnClientLabel: String?

    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private let directSession: URLSession
    private let stateKey = "qatvasl.last.state"
    private let historyKey = "qatvasl.state.history.v1"

    private var loopTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var proxySession: URLSession?
    private var proxySessionKey: ProxySessionKey?
    private var routeContextCache: (timestamp: Date, context: RouteContext)?
    private var notificationsAllowed = false
    private var hasCompletedFirstCheck = false

    var isDirectPathClean: Bool {
        !tunnelDetected && !systemProxyDetected
    }

    var routeModeLabel: String {
        switch (tunnelDetected, systemProxyDetected) {
        case (true, true):
            return "Route: VPN + PROXY"
        case (true, false):
            return "Route: VPN active"
        case (false, true):
            return "Route: PROXY active"
        case (false, false):
            return "Route: Direct path"
        }
    }

    init(settingsStore: SettingsStore, defaults: UserDefaults = .standard) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.directSession = Self.makeDirectSession()
        if
            let rawState = defaults.string(forKey: stateKey),
            let state = ConnectivityState(rawValue: rawState)
        {
            self.currentState = state
        } else {
            self.currentState = .offline
        }
        self.transitionHistory = Self.loadHistory(from: defaults, key: historyKey)

        settingsObserver = settingsStore.$settings
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartLoop()
            }

        Task { [weak self] in
            await self?.prepareNotifications()
        }

        restartLoop()
    }

    deinit {
        loopTask?.cancel()
        directSession.invalidateAndCancel()
        proxySession?.invalidateAndCancel()
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.runCheck()
        }
    }

    func clearHistory() {
        transitionHistory = []
        defaults.removeObject(forKey: historyKey)
    }

    private func restartLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            await runCheck()
            while !Task.isCancelled {
                let interval = settingsStore.settings.normalizedInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled {
                    break
                }
                await runCheck()
            }
        }
    }

    private func prepareNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsAllowed = true
        case .notDetermined:
            notificationsAllowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            notificationsAllowed = false
        }
    }

    private func runCheck() async {
        if isChecking {
            return
        }
        isChecking = true
        defer { isChecking = false }

        let settings = settingsStore.settings
        let routeContext = await detectRouteContextAsync()
        if tunnelDetected != routeContext.tunnelActive {
            tunnelDetected = routeContext.tunnelActive
        }
        if systemProxyDetected != routeContext.systemProxyActive {
            systemProxyDetected = routeContext.systemProxyActive
        }
        if vpnClientLabel != routeContext.vpnClientName {
            vpnClientLabel = routeContext.vpnClientName
        }
        async let domestic = probeDirect(
            id: "domestic",
            name: "Domestic",
            target: settings.domesticURL,
            timeout: settings.normalizedTimeout
        )
        async let global = probeDirect(
            id: "global",
            name: "Global",
            target: settings.globalURL,
            timeout: settings.normalizedTimeout
        )
        async let blockedDirect = probeDirect(
            id: "blocked_direct",
            name: "Restricted Site (Direct)",
            target: settings.blockedURL,
            timeout: settings.normalizedTimeout
        )
        async let blockedProxy = probeProxy(
            id: "blocked_proxy",
            name: "Restricted Site (VPN Route)",
            target: settings.blockedURL,
            settings: settings
        )

        let snapshot = await ProbeSnapshot(
            timestamp: Date(),
            domestic: domestic,
            global: global,
            blockedDirect: blockedDirect,
            blockedProxy: blockedProxy
        )

        let previousState = currentState
        let nextState = evaluate(snapshot, routeContext: routeContext)
        currentState = nextState
        defaults.set(nextState.rawValue, forKey: stateKey)

        lastSnapshot = snapshot
        lastCheckedAt = snapshot.timestamp
        let nextError = snapshot.allResults.first(where: { !$0.ok })?.error
        if latestError != nextError {
            latestError = nextError
        }

        if hasCompletedFirstCheck, previousState != nextState {
            appendTransition(from: previousState, to: nextState, at: snapshot.timestamp)
        }

        await maybeNotifyTransition(from: previousState, to: nextState, settings: settings)
    }

    private func evaluate(_ snapshot: ProbeSnapshot, routeContext: RouteContext) -> ConnectivityState {
        if routeContext.hasOverlay {
            if snapshot.domestic.ok || snapshot.global.ok || snapshot.blockedDirect.ok || snapshot.blockedProxy.ok {
                return .vpnOrProxyActive
            }
            return .offline
        }

        if snapshot.blockedDirect.ok {
            return .openInternet
        }
        if snapshot.blockedProxy.ok {
            return .vpnOK
        }
        if snapshot.domestic.ok && !snapshot.global.ok {
            return .domesticOnly
        }
        if snapshot.global.ok {
            return .globalLimited
        }
        return .offline
    }

    private struct RouteContext: Sendable {
        let tunnelActive: Bool
        let systemProxyActive: Bool
        let vpnClientName: String?

        var hasOverlay: Bool {
            tunnelActive || systemProxyActive
        }
    }

    private struct ProxySessionKey: Equatable {
        let host: String
        let port: Int
        let type: ProxyType
    }

    private func detectRouteContextAsync() async -> RouteContext {
        if
            let cached = routeContextCache,
            Date().timeIntervalSince(cached.timestamp) < 2
        {
            return cached.context
        }

        let context = await Task.detached(priority: .utility) {
            Self.detectRouteContext()
        }.value
        routeContextCache = (Date(), context)
        return context
    }

    private nonisolated static func detectRouteContext() -> RouteContext {
        let connectedServiceName = detectConnectedNetworkServiceName()
        let tunnelViaDefaultRoute = detectTunnelDefaultRouteActive()
        let tunnelActive = connectedServiceName != nil || tunnelViaDefaultRoute
        let systemProxyActive = detectSystemProxyActive()

        return RouteContext(
            tunnelActive: tunnelActive,
            systemProxyActive: systemProxyActive,
            vpnClientName: detectVpnClientName(
                tunnelActive: tunnelActive,
                systemProxyActive: systemProxyActive,
                connectedServiceName: connectedServiceName
            )
        )
    }

    private nonisolated static func detectVpnClientName(
        tunnelActive: Bool,
        systemProxyActive: Bool,
        connectedServiceName: String?
    ) -> String? {
        guard tunnelActive || systemProxyActive else {
            return nil
        }

        if let connectedServiceName {
            return connectedServiceName
        }

        if tunnelActive, let processName = detectLikelyVpnProcessName() {
            return processName
        }

        if tunnelActive {
            return "Unknown tunnel client"
        }

        return "Unknown proxy client"
    }

    private nonisolated static func detectTunnelDefaultRouteActive() -> Bool {
        if
            let defaultIPv4Interface = detectDefaultRouteInterface(arguments: ["-n", "get", "default"]),
            isTunnelInterfaceName(defaultIPv4Interface)
        {
            return true
        }

        if
            let defaultIPv6Interface = detectDefaultRouteInterface(arguments: ["-n", "get", "-inet6", "default"]),
            isTunnelInterfaceName(defaultIPv6Interface)
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

    private nonisolated static func isTunnelInterfaceName(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("utun") ||
            interfaceName.hasPrefix("tun") ||
            interfaceName.hasPrefix("tap") ||
            interfaceName.hasPrefix("ppp")
    }

    private nonisolated static func detectSystemProxyActive() -> Bool {
        guard
            let unmanaged = CFNetworkCopySystemProxySettings(),
            let settings = unmanaged.takeRetainedValue() as? [String: Any]
        else {
            return false
        }

        let httpEnabled = (settings[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.boolValue == true
        if
            httpEnabled,
            let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return true
        }

        let httpsEnabled = (settings[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber)?.boolValue == true
        if
            httpsEnabled,
            let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return true
        }

        let socksEnabled = (settings[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber)?.boolValue == true
        if
            socksEnabled,
            let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return true
        }

        return false
    }

    private nonisolated static func detectConnectedNetworkServiceName() -> String? {
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

    private nonisolated static func detectLikelyVpnProcessName() -> String? {
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

    private func maybeNotifyTransition(
        from previous: ConnectivityState,
        to current: ConnectivityState,
        settings: MonitorSettings
    ) async {
        if !hasCompletedFirstCheck {
            hasCompletedFirstCheck = true
            return
        }

        if previous == current || !settings.notificationsEnabled || !notificationsAllowed {
            return
        }

        if current.severity < previous.severity {
            await sendNotification(
                title: "QatVasl: Connectivity degraded",
                body: current.detail
            )
            return
        }

        if current.severity > previous.severity && settings.notifyOnRecovery {
            await sendNotification(
                title: "QatVasl: Connectivity recovered",
                body: current.detail
            )
        }
    }

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func appendTransition(from: ConnectivityState, to: ConnectivityState, at timestamp: Date) {
        var updated = transitionHistory
        updated.insert(StateTransition(from: from, to: to, timestamp: timestamp), at: 0)
        if updated.count > 40 {
            updated.removeLast(updated.count - 40)
        }
        transitionHistory = updated

        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func probeDirect(
        id: String,
        name: String,
        target: String,
        timeout: TimeInterval
    ) async -> ProbeResult {
        guard let url = URL(string: target) else {
            return ProbeResult(
                id: id,
                name: name,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Invalid URL"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("QatVasl/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        return await performProbe(
            id: id,
            name: name,
            target: target,
            request: request,
            session: directSession
        )
    }

    private func probeProxy(
        id: String,
        name: String,
        target: String,
        settings: MonitorSettings
    ) async -> ProbeResult {
        if !settings.proxyEnabled {
            return ProbeResult(
                id: id,
                name: name,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Proxy check disabled"
            )
        }

        guard let url = URL(string: target) else {
            return ProbeResult(
                id: id,
                name: name,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Invalid URL"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = settings.normalizedTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("QatVasl/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let session = proxySession(for: settings)

        return await performProbe(
            id: id,
            name: name,
            target: target,
            request: request,
            session: session
        )
    }

    private func performProbe(
        id: String,
        name: String,
        target: String,
        request: URLRequest,
        session: URLSession
    ) async -> ProbeResult {
        let started = Date()

        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            let ok = statusCode.map { (200..<500).contains($0) } ?? false

            return ProbeResult(
                id: id,
                name: name,
                target: target,
                ok: ok,
                statusCode: statusCode,
                latencyMs: latencyMs,
                error: ok ? nil : "Unexpected response"
            )
        } catch {
            return ProbeResult(
                id: id,
                name: name,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                error: map(error: error)
            )
        }
    }

    private nonisolated static func makeDirectSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    private func proxySession(for settings: MonitorSettings) -> URLSession {
        let key = ProxySessionKey(
            host: settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: settings.proxyPort,
            type: settings.proxyType
        )

        if let proxySession, proxySessionKey == key {
            return proxySession
        }

        proxySession?.invalidateAndCancel()
        let session = Self.makeProxySession(host: key.host, port: key.port, proxyType: key.type)
        proxySession = session
        proxySessionKey = key
        return session
    }

    private nonisolated static func makeProxySession(host: String, port: Int, proxyType: ProxyType) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = proxyDictionary(
            host: host,
            port: port,
            proxyType: proxyType
        )
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    private nonisolated static func proxyDictionary(host: String, port: Int, proxyType: ProxyType) -> [AnyHashable: Any] {
        switch proxyType {
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        }
    }

    private func map(error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "Timed out"
            case NSURLErrorNotConnectedToInternet:
                return "Not connected"
            case NSURLErrorCannotFindHost:
                return "Host not found"
            case NSURLErrorCannotConnectToHost:
                return "Connection refused"
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost"
            default:
                return nsError.localizedDescription
            }
        }
        return nsError.localizedDescription
    }

    private static func loadHistory(from defaults: UserDefaults, key: String) -> [StateTransition] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([StateTransition].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
