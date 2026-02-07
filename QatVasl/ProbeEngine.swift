import CFNetwork
import Foundation
import Network

final class ProbeEngine {
    private actor ResumeGate {
        private var resumed = false

        func claim() -> Bool {
            guard !resumed else {
                return false
            }
            resumed = true
            return true
        }
    }

    private struct ProxySessionKey: Equatable {
        let host: String
        let port: Int
        let type: ProxyType
    }

    private let directSession: URLSession
    private var proxySession: URLSession?
    private var proxySessionKey: ProxySessionKey?

    init(directSession: URLSession = ProbeEngine.makeDirectSession()) {
        self.directSession = directSession
    }

    deinit {
        directSession.invalidateAndCancel()
        proxySession?.invalidateAndCancel()
    }

    func runSnapshot(settings: MonitorSettings) async -> ProbeSnapshot {
        async let domestic = probeDirect(
            kind: .domestic,
            targets: settings.domesticProbeTargets,
            timeout: settings.normalizedTimeout
        )
        async let global = probeDirect(
            kind: .global,
            targets: settings.globalProbeTargets,
            timeout: settings.normalizedTimeout
        )
        async let restrictedDirect = probeDirect(
            kind: .restrictedDirect,
            targets: settings.blockedProbeTargets,
            timeout: settings.normalizedTimeout
        )
        async let restrictedViaProxy = probeProxy(
            kind: .restrictedViaProxy,
            targets: settings.blockedProbeTargets,
            settings: settings
        )

        return await ProbeSnapshot(
            timestamp: Date(),
            domestic: domestic,
            global: global,
            blockedDirect: restrictedDirect,
            blockedProxy: restrictedViaProxy
        )
    }

    func isProxyEndpointConnected(settings: MonitorSettings) async -> Bool {
        guard settings.proxyEnabled else {
            return false
        }

        let host = settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, (1...65535).contains(settings.proxyPort) else {
            return false
        }

        let timeout = min(settings.normalizedTimeout, 2.5)
        return await Self.tcpConnect(host: host, port: settings.proxyPort, timeout: timeout)
    }

    func runCriticalServices(settings: MonitorSettings) async -> [CriticalServiceResult] {
        let services = settings.criticalServices.filter(\.enabled)
        guard !services.isEmpty else {
            return []
        }

        let timeout = min(settings.normalizedTimeout, 10)
        let proxySession = settings.proxyEnabled ? proxySession(for: settings) : nil
        var results: [CriticalServiceResult] = []
        results.reserveCapacity(services.count)

        for service in services {
            let directResult: ServiceRouteProbeResult?
            if service.checkDirect {
                directResult = await probeServiceRoute(
                    target: service.url,
                    timeout: timeout,
                    session: directSession,
                    route: .direct
                )
            } else {
                directResult = nil
            }

            let proxyResult: ServiceRouteProbeResult?
            if service.checkProxy {
                if let proxySession {
                    proxyResult = await probeServiceRoute(
                        target: service.url,
                        timeout: timeout,
                        session: proxySession,
                        route: .proxy
                    )
                } else {
                    proxyResult = ServiceRouteProbeResult(
                        route: .proxy,
                        ok: false,
                        statusCode: nil,
                        latencyMs: nil,
                        error: "Proxy disabled"
                    )
                }
            } else {
                proxyResult = nil
            }

            results.append(
                CriticalServiceResult(
                    id: service.id,
                    name: service.name,
                    url: service.url,
                    direct: directResult,
                    proxy: proxyResult
                )
            )
        }

        return results
    }

    private func probeDirect(
        kind: ProbeKind,
        targets: [String],
        timeout: TimeInterval
    ) async -> ProbeResult {
        let candidates = sanitizedTargets(targets)
        guard !candidates.isEmpty else {
            return missingTargetResult(kind: kind)
        }

        var lastFailure = missingTargetResult(kind: kind)
        for target in candidates {
            let result = await probeDirectSingle(kind: kind, target: target, timeout: timeout)
            if result.ok {
                return result
            }
            lastFailure = result
        }

        return lastFailure
    }

    private func probeProxy(
        kind: ProbeKind,
        targets: [String],
        settings: MonitorSettings
    ) async -> ProbeResult {
        let candidates = sanitizedTargets(targets)
        guard !candidates.isEmpty else {
            return missingTargetResult(kind: kind)
        }

        let primaryTarget = candidates.first ?? "N/A"
        if !settings.proxyEnabled {
            return ProbeResult(
                kind: kind,
                target: primaryTarget,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Proxy check disabled"
            )
        }

        let session = proxySession(for: settings)
        var lastFailure = ProbeResult(
            kind: kind,
            target: primaryTarget,
            ok: false,
            statusCode: nil,
            latencyMs: nil,
            error: "Proxy probe failed"
        )

        for target in candidates {
            let result = await probeProxySingle(
                kind: kind,
                target: target,
                timeout: settings.normalizedTimeout,
                session: session
            )
            if result.ok {
                return result
            }
            lastFailure = result
        }

        return lastFailure
    }

    private func probeDirectSingle(
        kind: ProbeKind,
        target: String,
        timeout: TimeInterval
    ) async -> ProbeResult {
        guard let url = URL(string: target) else {
            return ProbeResult(
                kind: kind,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Invalid URL"
            )
        }

        let request = makeRequest(url: url, timeout: timeout)
        return await performProbe(
            kind: kind,
            target: target,
            request: request,
            session: directSession
        )
    }

    private func probeProxySingle(
        kind: ProbeKind,
        target: String,
        timeout: TimeInterval,
        session: URLSession
    ) async -> ProbeResult {
        guard let url = URL(string: target) else {
            return ProbeResult(
                kind: kind,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Invalid URL"
            )
        }

        let request = makeRequest(url: url, timeout: timeout)
        return await performProbe(
            kind: kind,
            target: target,
            request: request,
            session: session
        )
    }

    private func sanitizedTargets(_ targets: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        results.reserveCapacity(targets.count)

        for raw in targets {
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

    private func missingTargetResult(kind: ProbeKind) -> ProbeResult {
        ProbeResult(
            kind: kind,
            target: "N/A",
            ok: false,
            statusCode: nil,
            latencyMs: nil,
            error: "No websites configured"
        )
    }

    private func makeRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("QatVasl/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func performProbe(
        kind: ProbeKind,
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
                kind: kind,
                target: target,
                ok: ok,
                statusCode: statusCode,
                latencyMs: latencyMs,
                error: ok ? nil : "Unexpected response"
            )
        } catch {
            return ProbeResult(
                kind: kind,
                target: target,
                ok: false,
                statusCode: nil,
                latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                error: map(error: error)
            )
        }
    }

    private func probeServiceRoute(
        target: String,
        timeout: TimeInterval,
        session: URLSession,
        route: RouteKind
    ) async -> ServiceRouteProbeResult {
        guard let url = URL(string: target) else {
            return ServiceRouteProbeResult(
                route: route,
                ok: false,
                statusCode: nil,
                latencyMs: nil,
                error: "Invalid URL"
            )
        }

        let request = makeRequest(url: url, timeout: timeout)
        let started = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            let ok = statusCode.map { (200..<500).contains($0) } ?? false

            return ServiceRouteProbeResult(
                route: route,
                ok: ok,
                statusCode: statusCode,
                latencyMs: latencyMs,
                error: ok ? nil : "Unexpected response"
            )
        } catch {
            return ServiceRouteProbeResult(
                route: route,
                ok: false,
                statusCode: nil,
                latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                error: map(error: error)
            )
        }
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

    private nonisolated static func makeDirectSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    private nonisolated static func makeProxySession(host: String, port: Int, proxyType: ProxyType) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = proxyDictionary(host: host, port: port, proxyType: proxyType)
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

    private nonisolated static func tcpConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let resumeGate = ResumeGate()
            let finish: @Sendable (Bool) -> Void = { value in
                Task {
                    guard await resumeGate.claim() else {
                        return
                    }
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
        }
    }
}
