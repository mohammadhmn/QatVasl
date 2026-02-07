import Combine
import Foundation
import UserNotifications

@MainActor
final class NetworkMonitor: ObservableObject {
    private struct StateChange {
        let previous: ConnectivityState
        let current: ConnectivityState
        let timestamp: Date
    }

    private enum Limits {
        static let transitionHistory = 40
        static let healthSampleHistory = 2_000
        static let healthSampleRetentionSeconds: TimeInterval = 7 * 24 * 60 * 60
        static let settingsRestartDebounceMs = 700
        static let persistenceCoalesceSeconds: TimeInterval = 3
        static let persistenceMinFlushIntervalSeconds: TimeInterval = 45
    }

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
    private var persistenceFlushTask: Task<Void, Never>?
    private var notificationsAllowed = false
    private var lastNotificationSentAt: Date?
    private var lastCriticalServicesCheckAt: Date?
    private var lastPersistenceFlushAt: Date?
    private var pendingHistoryPersistence = false
    private var pendingSamplesPersistence = false
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

        let uptimeCount = recent.filter { !Self.isOutageState($0.state) }.count
        let uptimePercent = Int((Double(uptimeCount) / Double(recent.count) * 100).rounded())
        let averageLatencyValues = recent.compactMap(\.averageLatencyMs)
        let averageLatencyMs = averageLatencyValues.isEmpty
            ? nil
            : Int((Double(averageLatencyValues.reduce(0, +)) / Double(averageLatencyValues.count)).rounded())
        let dropCount = transitionHistory.filter {
            $0.timestamp >= Date().addingTimeInterval(-24 * 60 * 60) && Self.isOutageState($0.to)
        }.count

        let orderedSamples = recent.sorted { $0.timestamp < $1.timestamp }
        var outageStart: Date?
        var recoveries: [TimeInterval] = []

        for sample in orderedSamples {
            if Self.isOutageState(sample.state) {
                if outageStart == nil {
                    outageStart = sample.timestamp
                }
            } else if let start = outageStart {
                recoveries.append(sample.timestamp.timeIntervalSince(start))
                outageStart = nil
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
            .map(\.normalizedInterval)
            .removeDuplicates()
            .debounce(for: .milliseconds(Limits.settingsRestartDebounceMs), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartLoop(runImmediately: false)
            }

        Task { [weak self] in
            await self?.prepareNotifications()
        }

        restartLoop(runImmediately: true)
    }

    deinit {
        loopTask?.cancel()
        persistenceFlushTask?.cancel()
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.runCheck()
        }
    }

    func clearHistory() {
        transitionHistory = []
        healthSamples = []
        pendingHistoryPersistence = false
        pendingSamplesPersistence = false
        persistenceFlushTask?.cancel()
        persistenceFlushTask = nil
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: samplesKey)
    }

    private func restartLoop(runImmediately: Bool) {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            guard let self else { return }
            if runImmediately {
                await runCheck()
            }
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
        guard !isChecking else {
            return
        }
        isChecking = true
        defer { isChecking = false }

        let settings = settingsStore.settings
        let routeContext = await routeInspector.inspect()
        let snapshot = await probeEngine.runSnapshot(settings: settings)
        let timestamp = Date()
        await refreshCriticalServicesIfNeeded(settings: settings, timestamp: timestamp)
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
        let stateChange = applyAssessment(assessment, snapshot: snapshot)

        if hasCompletedFirstCheck, stateChange.previous != stateChange.current {
            appendTransition(from: stateChange.previous, to: stateChange.current, at: stateChange.timestamp)
        }

        await maybeNotifyTransition(from: stateChange.previous, to: stateChange.current, settings: settings)
    }

    private func refreshCriticalServicesIfNeeded(settings: MonitorSettings, timestamp: Date) async {
        guard shouldRefreshCriticalServices(now: timestamp, interval: settings.normalizedInterval) else {
            return
        }

        criticalServiceResults = await probeEngine.runCriticalServices(settings: settings)
        lastCriticalServicesCheckAt = timestamp
    }

    private func applyAssessment(_ assessment: ConnectivityAssessment, snapshot: ProbeSnapshot) -> StateChange {
        let previous = currentState
        let next = assessment.state

        if currentState != next {
            currentState = next
            defaults.set(next.rawValue, forKey: stateKey)
        }
        if diagnosis != assessment.diagnosis {
            diagnosis = assessment.diagnosis
        }
        if routeIndicators != assessment.routeIndicators {
            routeIndicators = assessment.routeIndicators
        }

        lastSnapshot = snapshot
        lastCheckedAt = snapshot.timestamp
        let nextError = snapshot.allResults.first(where: { !$0.ok })?.error
        if latestError != nextError {
            latestError = nextError
        }
        appendHealthSample(state: next, snapshot: snapshot, timestamp: snapshot.timestamp)

        return StateChange(previous: previous, current: next, timestamp: snapshot.timestamp)
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
        if updated.count > Limits.transitionHistory {
            updated.removeLast(updated.count - Limits.transitionHistory)
        }
        transitionHistory = updated

        pendingHistoryPersistence = true
        schedulePersistenceFlushIfNeeded()
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

        let cutoff = Date().addingTimeInterval(-Limits.healthSampleRetentionSeconds)
        updated.removeAll { $0.timestamp < cutoff }
        if updated.count > Limits.healthSampleHistory {
            updated.removeLast(updated.count - Limits.healthSampleHistory)
        }

        healthSamples = updated
        pendingSamplesPersistence = true
        schedulePersistenceFlushIfNeeded()
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

    private static func isOutageState(_ state: ConnectivityState) -> Bool {
        state == .offline || state == .vpnIssue
    }

    private func schedulePersistenceFlushIfNeeded() {
        guard persistenceFlushTask == nil else {
            return
        }

        let now = Date()
        let earliestFlush = now.addingTimeInterval(Limits.persistenceCoalesceSeconds)
        let nextAllowedFlush = lastPersistenceFlushAt.map {
            $0.addingTimeInterval(Limits.persistenceMinFlushIntervalSeconds)
        } ?? earliestFlush
        let flushDate = max(earliestFlush, nextAllowedFlush)
        let delay = max(0, flushDate.timeIntervalSince(now))
        let sleepNanos = UInt64((delay * 1_000_000_000).rounded())

        persistenceFlushTask = Task { [weak self] in
            if sleepNanos > 0 {
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            self?.flushPendingPersistence(force: false)
        }
    }

    private func flushPendingPersistence(force: Bool) {
        persistenceFlushTask = nil
        guard pendingHistoryPersistence || pendingSamplesPersistence else {
            return
        }

        let now = Date()
        if
            !force,
            let lastPersistenceFlushAt,
            now.timeIntervalSince(lastPersistenceFlushAt) < Limits.persistenceMinFlushIntervalSeconds
        {
            schedulePersistenceFlushIfNeeded()
            return
        }

        var wroteAny = false

        if pendingHistoryPersistence, let data = try? JSONEncoder().encode(transitionHistory) {
            defaults.set(data, forKey: historyKey)
            pendingHistoryPersistence = false
            wroteAny = true
        }

        if pendingSamplesPersistence, let data = try? JSONEncoder().encode(healthSamples) {
            defaults.set(data, forKey: samplesKey)
            pendingSamplesPersistence = false
            wroteAny = true
        }

        if wroteAny {
            lastPersistenceFlushAt = now
        }

        if !force, (pendingHistoryPersistence || pendingSamplesPersistence) {
            schedulePersistenceFlushIfNeeded()
        }
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
