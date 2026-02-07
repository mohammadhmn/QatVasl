import Combine
import Foundation
import UserNotifications

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var currentState: ConnectivityState
    @Published private(set) var diagnosis: ConnectivityDiagnosis
    @Published private(set) var routeIndicators: [RouteIndicator]
    @Published private(set) var lastSnapshot: ProbeSnapshot?
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
        return ConnectivityState.fromStoredRawValue(rawState) ?? .checking
    }
}
