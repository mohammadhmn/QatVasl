import Combine
import Foundation

@MainActor
final class IranPulseMonitor: ObservableObject {
    private enum Limits {
        static let maxBackoffMultiplier = 6
        static let maxLoopDelaySeconds: TimeInterval = 30 * 60
    }

    @Published private(set) var snapshot: IranPulseSnapshot
    @Published private(set) var isChecking = false
    @Published private(set) var latestError: String?

    private let settingsStore: SettingsStore
    private let defaults: UserDefaults
    private let storageKey = "qatvasl.iranPulse.snapshot.v1"
    private let vanillappProvider: VanillappIranPulseProvider
    private let ooniProvider: OoniIranPulseProvider

    private var loopTask: Task<Void, Never>?
    private var settingsObserver: AnyCancellable?
    private var backoffMultiplier = 1

    init(
        settingsStore: SettingsStore,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.settingsStore = settingsStore
        self.defaults = defaults
        self.vanillappProvider = VanillappIranPulseProvider(session: session)
        self.ooniProvider = OoniIranPulseProvider(session: session)
        self.snapshot = Self.loadSnapshot(from: defaults, key: storageKey) ?? .initial()

        settingsObserver = settingsStore.$settings
            .dropFirst()
            .sink { [weak self] _ in
                self?.restartLoop(runImmediately: false)
            }

        restartLoop(runImmediately: true)
    }

    deinit {
        loopTask?.cancel()
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.runCheck(forceRefresh: true)
        }
    }

    func diagnosticsReport() -> String {
        let providersText: String
        if snapshot.providers.isEmpty {
            providersText = "- none"
        } else {
            providersText = snapshot.providers
                .map { provider in
                    let scoreText = provider.score.map(String.init) ?? "N/A"
                    let errorText = provider.error ?? "none"
                    let ageText: String
                    if let capturedAt = provider.capturedAt {
                        ageText = "\(Int(Date().timeIntervalSince(capturedAt)))s ago"
                    } else {
                        ageText = "unknown"
                    }
                    return "- \(provider.source.title): \(provider.severity.title) · score \(scoreText) · confidence \(Int((provider.confidence * 100).rounded()))% · stale \(provider.stale ? "yes" : "no") · age \(ageText) · error \(errorText)"
                }
                .joined(separator: "\n")
        }

        return """
        Iran Pulse
        - Summary: \(snapshot.summary)
        - Score: \(snapshot.score.map(String.init) ?? "N/A")
        - Severity: \(snapshot.severity.title)
        - Confidence: \(Int((snapshot.confidence * 100).rounded()))%
        - Last updated: \(snapshot.lastUpdated.formatted(date: .abbreviated, time: .standard))
        - Checking: \(isChecking ? "yes" : "no")
        - Last error: \(latestError ?? "none")

        Providers
        \(providersText)
        """
    }

    private func restartLoop(runImmediately: Bool) {
        loopTask?.cancel()

        loopTask = Task { [weak self] in
            guard let self else {
                return
            }

            if runImmediately {
                await runCheck()
            }

            while !Task.isCancelled {
                let delay = loopDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else {
                    break
                }
                await runCheck()
            }
        }
    }

    private func loopDelay() -> TimeInterval {
        let base = settingsStore.settings.normalizedIranPulseInterval
        let adaptive = base * Double(backoffMultiplier)
        return min(adaptive, Limits.maxLoopDelaySeconds)
    }

    private func runCheck(forceRefresh: Bool = false) async {
        guard !isChecking else {
            return
        }
        isChecking = true
        defer { isChecking = false }

        let settings = settingsStore.settings
        let now = Date()

        guard settings.iranPulseEnabled else {
            latestError = nil
            backoffMultiplier = 1
            snapshot = .disabled(now: now)
            persistSnapshot(snapshot)
            return
        }

        var providerTasks: [Task<IranPulseProviderSnapshot, Never>] = []
        if settings.iranPulseVanillappEnabled {
            providerTasks.append(
                Task { [vanillappProvider] in
                    await vanillappProvider.fetchSnapshot(forceRefresh: forceRefresh)
                }
            )
        }
        if settings.iranPulseOoniEnabled {
            providerTasks.append(
                Task { [ooniProvider] in
                    await ooniProvider.fetchSnapshot(forceRefresh: forceRefresh)
                }
            )
        }

        guard !providerTasks.isEmpty else {
            latestError = nil
            backoffMultiplier = 1
            snapshot = .noProviders(now: now)
            persistSnapshot(snapshot)
            return
        }

        var providerSnapshots: [IranPulseProviderSnapshot] = []
        providerSnapshots.reserveCapacity(providerTasks.count)
        for task in providerTasks {
            providerSnapshots.append(await task.value)
        }
        providerSnapshots.sort { $0.source.rawValue < $1.source.rawValue }

        let merged = mergeProviderSnapshots(providerSnapshots, now: now)
        snapshot = merged
        persistSnapshot(merged)

        let hasData = providerSnapshots.contains { $0.score != nil }
        if hasData {
            latestError = nil
            backoffMultiplier = 1
        } else {
            latestError = providerSnapshots.compactMap(\.error).first ?? "No provider data"
            backoffMultiplier = min(backoffMultiplier * 2, Limits.maxBackoffMultiplier)
        }
    }

    private func mergeProviderSnapshots(_ providers: [IranPulseProviderSnapshot], now: Date) -> IranPulseSnapshot {
        guard !providers.isEmpty else {
            return .noProviders(now: now)
        }

        let scoredProviders = providers.compactMap { provider -> (score: Int, weight: Double, confidence: Double)? in
            guard let score = provider.score else {
                return nil
            }

            let baseWeight = sourceWeight(for: provider.source)
            let confidenceWeight = max(0.2, min(provider.confidence, 1))
            return (score, baseWeight * confidenceWeight, provider.confidence)
        }

        guard !scoredProviders.isEmpty else {
            let errorCount = providers.compactMap(\.error).count
            let message = errorCount > 0
                ? "Iran pulse unavailable (\(errorCount) source error\(errorCount > 1 ? "s" : ""))."
                : "Iran pulse unavailable."

            return IranPulseSnapshot(
                score: nil,
                severity: .unknown,
                confidence: 0,
                summary: message,
                providers: providers,
                lastUpdated: now
            )
        }

        let weightedScoreSum = scoredProviders.reduce(0) { $0 + (Double($1.score) * $1.weight) }
        let weightSum = scoredProviders.reduce(0) { $0 + $1.weight }
        var mergedScore = Int((weightedScoreSum / max(weightSum, 0.0001)).rounded())

        let staleCount = providers.filter(\.stale).count
        if staleCount == providers.count {
            mergedScore = max(0, mergedScore - 18)
        } else if staleCount > 0 {
            mergedScore = max(0, mergedScore - 8)
        }

        let mergedSeverity = Self.severity(for: mergedScore)
        let mergedConfidence = min(
            1,
            max(
                0,
                scoredProviders.reduce(0) { $0 + ($1.confidence * $1.weight) } / max(weightSum, 0.0001)
            )
        )

        let errorCount = providers.compactMap(\.error).count
        var summaryParts: [String] = [
            "Iran pulse \(mergedSeverity.title) · \(mergedScore)/100",
        ]
        if staleCount > 0 {
            summaryParts.append("\(staleCount) stale")
        }
        if errorCount > 0 {
            summaryParts.append("\(errorCount) source error\(errorCount > 1 ? "s" : "")")
        }

        return IranPulseSnapshot(
            score: mergedScore,
            severity: mergedSeverity,
            confidence: mergedConfidence,
            summary: summaryParts.joined(separator: " · "),
            providers: providers,
            lastUpdated: now
        )
    }

    private func sourceWeight(for source: IranPulseSource) -> Double {
        switch source {
        case .vanillapp:
            return 0.7
        case .ooni:
            return 0.3
        }
    }

    private func persistSnapshot(_ snapshot: IranPulseSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private static func loadSnapshot(from defaults: UserDefaults, key: String) -> IranPulseSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(IranPulseSnapshot.self, from: data)
    }

    static func severity(for score: Int) -> IranPulseSeverity {
        if score >= 80 {
            return .normal
        }
        if score >= 50 {
            return .degraded
        }
        return .severe
    }
}

private struct VanillappIranPulseProvider {
    private struct Response: Decodable {
        let internalDatacenters: [String: Datacenter]
        let externalDatacenters: [String: Datacenter]
        let timestamp: Double?

        enum CodingKeys: String, CodingKey {
            case internalDatacenters = "internal"
            case externalDatacenters = "external"
            case timestamp
        }
    }

    private struct Datacenter: Decodable {
        let status: Status?
        let cachedAt: Double?

        enum CodingKeys: String, CodingKey {
            case status
            case cachedAt = "cached_at"
        }
    }

    private struct Status: Decodable {
        let level: Int?
        let averageLatency: Double?

        enum CodingKeys: String, CodingKey {
            case level
            case averageLatency = "average_latency"
        }
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://radar.vanillapp.ir/api/radar/monitoring/all")!

    init(session: URLSession) {
        self.session = session
    }

    func fetchSnapshot(forceRefresh: Bool) async -> IranPulseProviderSnapshot {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 16
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200 ... 299).contains(http.statusCode) else {
                if http.statusCode == 429 {
                    return errorSnapshot(message: "Vanillapp rate limited (429).")
                }
                return errorSnapshot(message: "Vanillapp HTTP \(http.statusCode).")
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return mapResponse(decoded)
        } catch {
            return errorSnapshot(message: "Vanillapp fetch failed: \(error.localizedDescription)")
        }
    }

    private func mapResponse(_ response: Response) -> IranPulseProviderSnapshot {
        let internalValues = Array(response.internalDatacenters.values)
        let externalValues = Array(response.externalDatacenters.values)
        let allDatacenters = internalValues + externalValues

        let levels = allDatacenters
            .compactMap { $0.status?.level }
            .filter { (0 ... 4).contains($0) }

        guard !levels.isEmpty else {
            return errorSnapshot(message: "Vanillapp returned no status levels.")
        }

        let totalDatacenters = allDatacenters.count
        let degradedCount = levels.filter { $0 >= 2 }.count
        let averageLevel = Double(levels.reduce(0, +)) / Double(levels.count)
        let degradedRatio = Double(degradedCount) / Double(levels.count)

        let rawScore = ((4 - averageLevel) / 4 * 100) - (degradedRatio * 20)
        let score = Int(max(0, min(100, rawScore)).rounded())
        let severity = IranPulseMonitor.severity(for: score)

        let capturedCandidates = [
            response.timestamp,
            allDatacenters.compactMap(\.cachedAt).max(),
        ].compactMap { $0 }
        let capturedAt = capturedCandidates.max().map { Date(timeIntervalSince1970: $0) }
        let ageSeconds = capturedAt.map { Date().timeIntervalSince($0) } ?? 0
        let stale = ageSeconds > (20 * 60)

        var confidence = 0.82
        let coverage = totalDatacenters > 0 ? Double(levels.count) / Double(totalDatacenters) : 0
        if coverage < 0.7 {
            confidence -= 0.15
        }
        if coverage < 0.4 {
            confidence -= 0.15
        }
        if stale {
            confidence -= 0.2
        }
        if ageSeconds > (45 * 60) {
            confidence -= 0.2
        }
        confidence = min(1, max(0.1, confidence))

        let averageLatencyValues = allDatacenters.compactMap { $0.status?.averageLatency }
        let averageLatency = averageLatencyValues.isEmpty
            ? nil
            : averageLatencyValues.reduce(0, +) / Double(averageLatencyValues.count)

        var details: [String: String] = [
            "datacenters_total": "\(totalDatacenters)",
            "status_coverage": "\(levels.count)",
            "degraded_nodes": "\(degradedCount)",
            "average_level": String(format: "%.2f", averageLevel),
        ]
        if let averageLatency {
            details["average_latency"] = String(format: "%.2f", averageLatency)
        }
        if let capturedAt {
            details["captured_at"] = Self.iso8601.string(from: capturedAt)
            details["age_seconds"] = "\(Int(max(0, ageSeconds).rounded()))"
        }

        return IranPulseProviderSnapshot(
            source: .vanillapp,
            score: score,
            severity: severity,
            confidence: confidence,
            capturedAt: capturedAt,
            stale: stale,
            summary: "\(degradedCount)/\(levels.count) nodes degraded across \(totalDatacenters) datacenters.",
            details: details,
            error: nil
        )
    }

    private func errorSnapshot(message: String) -> IranPulseProviderSnapshot {
        IranPulseProviderSnapshot(
            source: .vanillapp,
            score: nil,
            severity: .unknown,
            confidence: 0,
            capturedAt: nil,
            stale: false,
            summary: message,
            details: [:],
            error: message
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct OoniIranPulseProvider {
    private struct Response: Decodable {
        let results: [Measurement]
    }

    private struct Measurement: Decodable {
        let anomaly: Bool
        let confirmed: Bool
        let failure: Bool
        let measurementStartTime: String?

        enum CodingKeys: String, CodingKey {
            case anomaly
            case confirmed
            case failure
            case measurementStartTime = "measurement_start_time"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            anomaly = Self.decodeFlag(from: container, key: .anomaly)
            confirmed = Self.decodeFlag(from: container, key: .confirmed)
            failure = Self.decodeFlag(from: container, key: .failure)
            measurementStartTime = try container.decodeIfPresent(String.self, forKey: .measurementStartTime)
        }

        private static func decodeFlag(
            from container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys
        ) -> Bool {
            if let value = try? container.decode(Bool.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Int.self, forKey: key) {
                return value != 0
            }
            if let value = try? container.decode(String.self, forKey: key) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized.isEmpty || normalized == "false" || normalized == "ok" {
                    return false
                }
                return true
            }
            return false
        }
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.ooni.io/api/v1/measurements")!

    init(session: URLSession) {
        self.session = session
    }

    func fetchSnapshot(forceRefresh: Bool) async -> IranPulseProviderSnapshot {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "probe_cc", value: "IR"),
            URLQueryItem(name: "test_name", value: "web_connectivity"),
            URLQueryItem(name: "limit", value: "40"),
        ]

        guard let url = components?.url else {
            return errorSnapshot(message: "OONI URL build failed.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.cachePolicy = forceRefresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200 ... 299).contains(http.statusCode) else {
                if http.statusCode == 429 {
                    return errorSnapshot(message: "OONI rate limited (429).")
                }
                return errorSnapshot(message: "OONI HTTP \(http.statusCode).")
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return mapResponse(decoded)
        } catch {
            return errorSnapshot(message: "OONI fetch failed: \(error.localizedDescription)")
        }
    }

    private func mapResponse(_ response: Response) -> IranPulseProviderSnapshot {
        guard !response.results.isEmpty else {
            return errorSnapshot(message: "OONI returned no measurements.")
        }

        let sampleCount = response.results.count
        let anomalyCount = response.results.filter(\.anomaly).count
        let confirmedCount = response.results.filter(\.confirmed).count
        let failureCount = response.results.filter(\.failure).count

        let weightedBlocked = (Double(confirmedCount) * 1.3)
            + (Double(anomalyCount) * 1.0)
            + (Double(failureCount) * 0.9)
        let blockedRatio = min(1, weightedBlocked / Double(sampleCount))

        let score = Int(((1 - blockedRatio) * 100).rounded())
        let severity = IranPulseMonitor.severity(for: score)

        let newestSampleAt = response.results
            .compactMap { measurement in
                measurement.measurementStartTime.flatMap(Self.parseDate)
            }
            .max()
        let ageSeconds = newestSampleAt.map { Date().timeIntervalSince($0) } ?? 0
        let stale = ageSeconds > 3600

        var confidence = 0.62 + min(0.28, Double(sampleCount) / 100)
        if sampleCount < 10 {
            confidence -= 0.2
        }
        if stale {
            confidence -= 0.2
        }
        confidence = min(1, max(0.1, confidence))

        var details: [String: String] = [
            "sample_count": "\(sampleCount)",
            "confirmed_count": "\(confirmedCount)",
            "anomaly_count": "\(anomalyCount)",
            "failure_count": "\(failureCount)",
            "blocked_ratio": String(format: "%.3f", blockedRatio),
        ]
        if let newestSampleAt {
            details["newest_sample_at"] = Self.iso8601.string(from: newestSampleAt)
            details["age_seconds"] = "\(Int(max(0, ageSeconds).rounded()))"
        }

        return IranPulseProviderSnapshot(
            source: .ooni,
            score: score,
            severity: severity,
            confidence: confidence,
            capturedAt: newestSampleAt,
            stale: stale,
            summary: "\(confirmedCount) confirmed, \(failureCount) failure, \(anomalyCount) anomaly in \(sampleCount) samples.",
            details: details,
            error: nil
        )
    }

    private func errorSnapshot(message: String) -> IranPulseProviderSnapshot {
        IranPulseProviderSnapshot(
            source: .ooni,
            score: nil,
            severity: .unknown,
            confidence: 0,
            capturedAt: nil,
            stale: false,
            summary: message,
            details: [:],
            error: message
        )
    }

    private nonisolated static func parseDate(_ value: String) -> Date? {
        if let date = iso8601WithFractional.date(from: value) {
            return date
        }
        return iso8601.date(from: value)
    }

    private nonisolated(unsafe) static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
