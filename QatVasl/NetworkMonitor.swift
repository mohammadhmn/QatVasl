import Combine
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
    @Published private(set) var vpnDetected = false
    @Published private(set) var proxyDetected = false
    @Published private(set) var vpnClientLabel: String?

    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private let routeInspector: RouteInspector
    private let probeEngine: ProbeEngine

    private let stateKey = "qatvasl.last.state"
    private let historyKey = "qatvasl.state.history.v1"

    private var loopTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var notificationsAllowed = false
    private var hasCompletedFirstCheck = false

    var isDirectPathClean: Bool {
        !vpnDetected
    }

    var routeModeLabel: String {
        switch (vpnDetected, proxyDetected) {
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
        let routeContext = await routeInspector.inspect()
        async let snapshotTask = probeEngine.runSnapshot(settings: settings)
        async let proxyConnectedTask = probeEngine.isProxyEndpointConnected(settings: settings)
        let snapshot = await snapshotTask
        let proxyConnected = await proxyConnectedTask
        apply(routeContext: routeContext, snapshot: snapshot, settings: settings, proxyConnected: proxyConnected)
        let previousState = currentState
        let nextState = ConnectivityStateEvaluator.evaluate(snapshot: snapshot, routeContext: routeContext)

        currentState = nextState
        defaults.set(nextState.rawValue, forKey: stateKey)

        lastSnapshot = snapshot
        lastCheckedAt = snapshot.timestamp
        latestError = snapshot.allResults.first(where: { !$0.ok })?.error

        if hasCompletedFirstCheck, previousState != nextState {
            appendTransition(from: previousState, to: nextState, at: snapshot.timestamp)
        }

        await maybeNotifyTransition(from: previousState, to: nextState, settings: settings)
    }

    private func apply(
        routeContext: RouteContext,
        snapshot: ProbeSnapshot,
        settings: MonitorSettings,
        proxyConnected: Bool
    ) {
        if vpnDetected != routeContext.vpnActive {
            vpnDetected = routeContext.vpnActive
        }
        let proxyIsWorking = settings.proxyEnabled && proxyConnected && snapshot.blockedProxy.ok
        if proxyDetected != proxyIsWorking {
            proxyDetected = proxyIsWorking
        }
        if vpnClientLabel != routeContext.vpnClientName {
            vpnClientLabel = routeContext.vpnClientName
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
