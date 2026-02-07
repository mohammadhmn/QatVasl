import Combine
import Foundation
import UserNotifications

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var currentState: ConnectivityState
    @Published private(set) var diagnosis: ConnectivityDiagnosis
    @Published private(set) var routeIndicators: [RouteIndicator]
    @Published private(set) var lastSnapshot: ProbeSnapshot?
    @Published private(set) var criticalServiceResults: [CriticalServiceResult]
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var latestError: String?
    @Published private(set) var transitionHistory: [StateTransition]
    @Published private(set) var healthSamples: [HealthSample]
    @Published private(set) var vpnDetected = false
    @Published private(set) var proxyDetected = false
    @Published private(set) var vpnClientLabel: String?

    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private let routeInspector: RouteInspector
    private let probeEngine: ProbeEngine

    private let stateKey = "qatvasl.last.state"
    private let historyKey = "qatvasl.state.history.v1"
    private let samplesKey = "qatvasl.health.samples.v1"

    private var loopTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var notificationsAllowed = false
    private var lastNotificationSentAt: Date?
    private var lastCriticalServicesCheckAt: Date?
    private var hasCompletedFirstCheck = false

    var displayState: ConnectivityState {
        if !hasCompletedFirstCheck && isChecking {
            return .checking
        }
        return currentState
    }

    var isDirectPathClean: Bool {
        !vpnDetected && !proxyDetected
    }

    var routeModeLabel: String {
        RouteSummaryFormatter.format(vpnActive: vpnDetected, proxyActive: proxyDetected)
    }

    var last24hSamples: [HealthSample] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return healthSamples.filter { $0.timestamp >= cutoff }
    }

    var timelineSummary24h: TimelineSummary {
        let recent = last24hSamples
        guard !recent.isEmpty else {
            return .empty
        }

        let uptimeCount = recent.filter { $0.state != .offline }.count
        let uptimePercent = Int((Double(uptimeCount) / Double(recent.count) * 100).rounded())
        let averageLatencyValues = recent.compactMap(\.averageLatencyMs)
        let averageLatencyMs = averageLatencyValues.isEmpty
            ? nil
            : Int((Double(averageLatencyValues.reduce(0, +)) / Double(averageLatencyValues.count)).rounded())
        let dropCount = transitionHistory.filter {
            $0.timestamp >= Date().addingTimeInterval(-24 * 60 * 60) && $0.to == .offline
        }.count

        let orderedSamples = recent.sorted { $0.timestamp < $1.timestamp }
        var offlineStart: Date?
        var recoveries: [TimeInterval] = []

        for sample in orderedSamples {
            if sample.state == .offline {
                if offlineStart == nil {
                    offlineStart = sample.timestamp
                }
            } else if let start = offlineStart {
                recoveries.append(sample.timestamp.timeIntervalSince(start))
                offlineStart = nil
            }
        }

        let meanRecoverySeconds = recoveries.isEmpty
            ? nil
            : Int((recoveries.reduce(0, +) / Double(recoveries.count)).rounded())

        return TimelineSummary(
            uptimePercent: uptimePercent,
            dropCount: dropCount,
            averageLatencyMs: averageLatencyMs,
            meanRecoverySeconds: meanRecoverySeconds,
            sampleCount: recent.count
        )
    }

    init(
        settingsStore: SettingsStore,
        defaults: UserDefaults = .standard,
        routeInspector: RouteInspector? = nil,
        probeEngine: ProbeEngine? = nil
    ) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.routeInspector = routeInspector ?? RouteInspector()
        self.probeEngine = probeEngine ?? ProbeEngine()

        self.currentState = Self.loadInitialState(from: defaults, key: stateKey)
        self.diagnosis = .initial
        self.routeIndicators = ConnectivityAssessment.initial.routeIndicators
        self.transitionHistory = Self.loadHistory(from: defaults, key: historyKey)
        self.healthSamples = Self.loadSamples(from: defaults, key: samplesKey)
        self.criticalServiceResults = []

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
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.runCheck()
        }
    }

    func clearHistory() {
        transitionHistory = []
        healthSamples = []
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: samplesKey)
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
        let routeContext = await routeInspector.inspect()
        let snapshot = await probeEngine.runSnapshot(settings: settings)
        let timestamp = Date()
        if shouldRefreshCriticalServices(now: timestamp, interval: settings.normalizedInterval) {
            criticalServiceResults = await probeEngine.runCriticalServices(settings: settings)
            lastCriticalServicesCheckAt = timestamp
        }
        let proxyEndpointConnected = await probeEngine.isProxyEndpointConnected(settings: settings)
        let proxyIsWorking = apply(
            routeContext: routeContext,
            snapshot: snapshot,
            settings: settings,
            proxyEndpointConnected: proxyEndpointConnected
        )

        let assessment = ConnectivityStateEvaluator.evaluate(
            snapshot: snapshot,
            routeContext: routeContext,
            proxyActive: proxyIsWorking,
            proxyEndpointConnected: proxyEndpointConnected
        )
        let previousState = currentState
        let nextState = assessment.state

        currentState = nextState
        diagnosis = assessment.diagnosis
        routeIndicators = assessment.routeIndicators
        defaults.set(nextState.rawValue, forKey: stateKey)

        lastSnapshot = snapshot
        lastCheckedAt = snapshot.timestamp
        latestError = snapshot.allResults.first(where: { !$0.ok })?.error
        appendHealthSample(state: nextState, snapshot: snapshot, timestamp: snapshot.timestamp)

        if hasCompletedFirstCheck, previousState != nextState {
            appendTransition(from: previousState, to: nextState, at: snapshot.timestamp)
        }

        await maybeNotifyTransition(from: previousState, to: nextState, settings: settings)
    }

    private func apply(
        routeContext: RouteContext,
        snapshot: ProbeSnapshot,
        settings: MonitorSettings,
        proxyEndpointConnected: Bool
    ) -> Bool {
        if vpnDetected != routeContext.vpnActive {
            vpnDetected = routeContext.vpnActive
        }
        let proxyIsWorking = settings.proxyEnabled && proxyEndpointConnected && snapshot.blockedProxy.ok
        if proxyDetected != proxyIsWorking {
            proxyDetected = proxyIsWorking
        }
        if vpnClientLabel != routeContext.vpnClientName {
            vpnClientLabel = routeContext.vpnClientName
        }
        return proxyIsWorking
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

        let now = Date()
        if !shouldSendNotification(at: now, settings: settings) {
            return
        }

        if current.severity < previous.severity {
            let didSend = await sendNotification(
                title: "QatVasl: Connectivity degraded",
                body: current.detail
            )
            if didSend {
                lastNotificationSentAt = now
            }
            return
        }

        if current.severity > previous.severity && settings.notifyOnRecovery {
            let didSend = await sendNotification(
                title: "QatVasl: Connectivity recovered",
                body: current.detail
            )
            if didSend {
                lastNotificationSentAt = now
            }
        }
    }

    private func sendNotification(title: String, body: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
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

    private static func loadHistory(from defaults: UserDefaults, key: String) -> [StateTransition] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([StateTransition].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func appendHealthSample(state: ConnectivityState, snapshot: ProbeSnapshot, timestamp: Date) {
        let latencyValues = snapshot.allResults.compactMap { probe in
            probe.ok ? probe.latencyMs : nil
        }
        let averageLatencyMs = latencyValues.isEmpty
            ? nil
            : Int((Double(latencyValues.reduce(0, +)) / Double(latencyValues.count)).rounded())

        var updated = healthSamples
        updated.insert(
            HealthSample(
                timestamp: timestamp,
                state: state,
                averageLatencyMs: averageLatencyMs,
                routeLabel: routeModeLabel
            ),
            at: 0
        )

        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        updated.removeAll { $0.timestamp < cutoff }
        if updated.count > 2_000 {
            updated.removeLast(updated.count - 2_000)
        }

        healthSamples = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: samplesKey)
        }
    }

    private static func loadSamples(from defaults: UserDefaults, key: String) -> [HealthSample] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([HealthSample].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func loadInitialState(from defaults: UserDefaults, key: String) -> ConnectivityState {
        guard let rawState = defaults.string(forKey: key) else {
            return .checking
        }
        return ConnectivityState(rawValue: rawState) ?? .checking
    }

    private func shouldSendNotification(at date: Date, settings: MonitorSettings) -> Bool {
        let cooldown = settings.normalizedNotificationCooldown
        if
            cooldown > 0,
            let lastNotificationSentAt,
            date.timeIntervalSince(lastNotificationSentAt) < cooldown
        {
            return false
        }

        if settings.quietHoursEnabled, isWithinQuietHours(date: date, settings: settings) {
            return false
        }

        return true
    }

    private func isWithinQuietHours(date: Date, settings: MonitorSettings) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = settings.normalizedQuietHoursStart
        let end = settings.normalizedQuietHoursEnd

        if start == end {
            return true
        }

        if start < end {
            return hour >= start && hour < end
        }

        return hour >= start || hour < end
    }

    private func shouldRefreshCriticalServices(now: Date, interval: TimeInterval) -> Bool {
        guard let lastCriticalServicesCheckAt else {
            return true
        }

        let refreshInterval = max(30, min(300, interval * 2))
        return now.timeIntervalSince(lastCriticalServicesCheckAt) >= refreshInterval
    }

    func diagnosticsReport(settings: MonitorSettings) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let lastSnapshotSummary: String
        if let lastSnapshot {
            lastSnapshotSummary = lastSnapshot.allResults
                .map { "\($0.name): \($0.summary) (\($0.target))" }
                .joined(separator: "\n")
        } else {
            lastSnapshotSummary = "No snapshot yet."
        }

        let servicesSummary: String
        if criticalServiceResults.isEmpty {
            servicesSummary = "No critical service checks yet."
        } else {
            servicesSummary = criticalServiceResults.map { service in
                let direct = service.direct?.summary ?? "—"
                let proxy = service.proxy?.summary ?? "—"
                return "\(service.name)\n  DIRECT: \(direct)\n  PROXY: \(proxy)"
            }.joined(separator: "\n")
        }

        let transitionsSummary: String
        if transitionHistory.isEmpty {
            transitionsSummary = "No recorded transitions."
        } else {
            transitionsSummary = transitionHistory.prefix(20).map { transition in
                "\(transition.label) at \(formatter.string(from: transition.timestamp))"
            }.joined(separator: "\n")
        }

        let timeline = timelineSummary24h

        return """
        QatVasl Diagnostics
        Generated: \(formatter.string(from: Date()))

        Status
        - State: \(displayState.shortLabel)
        - Detail: \(displayState.detail)
        - Route: \(routeModeLabel)
        - VPN client: \(vpnClientLabel ?? "Unknown")
        - Last check: \(lastCheckedAt.map { formatter.string(from: $0) } ?? "N/A")
        - Latest error: \(latestError ?? "N/A")

        Diagnosis
        - \(diagnosis.title)
        - \(diagnosis.explanation)
        - Actions:
        \(diagnosis.actions.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Timeline (24h)
        - Uptime: \(timeline.uptimePercent)%
        - Drops: \(timeline.dropCount)
        - Avg latency: \(timeline.averageLatencyMs.map { "\($0) ms" } ?? "N/A")
        - Mean recovery: \(timeline.meanRecoverySeconds.map { "\($0) s" } ?? "N/A")
        - Samples: \(timeline.sampleCount)

        Probe Snapshot
        \(lastSnapshotSummary)

        Critical Services
        \(servicesSummary)

        Recent Transitions
        \(transitionsSummary)

        Settings
        - Active ISP profile: \(settings.activeProfile?.name ?? "N/A")
        - Interval: \(Int(settings.intervalSeconds)) sec
        - Timeout: \(Int(settings.timeoutSeconds)) sec
        - Proxy: \(settings.proxyType.title) \(settings.proxyHost):\(settings.proxyPort) [enabled=\(settings.proxyEnabled)]
        - Notifications: enabled=\(settings.notificationsEnabled), recovery=\(settings.notifyOnRecovery), cooldown=\(Int(settings.notificationCooldownMinutes)) min
        - Quiet hours: enabled=\(settings.quietHoursEnabled), from=\(settings.quietHoursStart):00 to \(settings.quietHoursEnd):00
        """
    }
}
