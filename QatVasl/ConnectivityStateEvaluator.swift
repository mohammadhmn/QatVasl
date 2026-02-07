import Foundation

enum ConnectivityStateEvaluator {
    static func evaluate(
        snapshot: ProbeSnapshot,
        routeContext: RouteContext,
        proxyActive: Bool,
        proxyEndpointConnected: Bool
    ) -> ConnectivityAssessment {
        let routeIndicators = makeRouteIndicators(vpnActive: routeContext.vpnActive, proxyActive: proxyActive)
        let routeLine = RouteSummaryFormatter.format(vpnActive: routeContext.vpnActive, proxyActive: proxyActive)

        if routeContext.vpnActive {
            if snapshot.blockedProxy.ok || snapshot.blockedDirect.ok {
                return ConnectivityAssessment(
                    state: .usable,
                    diagnosis: ConnectivityDiagnosis(
                        title: "VPN route is active",
                        explanation: "Traffic is currently routed through a system VPN/TUN path and restricted-service checks are passing.",
                        actions: [
                            "Keep VPN connected if your apps are working.",
                            "Use Refresh Now after VPN node/profile changes.",
                            "Disable VPN briefly if you need a true direct-path test.",
                        ]
                    ),
                    routeIndicators: routeIndicators,
                    detailLine: routeLine
                )
            }

            if snapshot.global.ok || snapshot.domestic.ok {
                return ConnectivityAssessment(
                    state: .vpnIssue,
                    diagnosis: ConnectivityDiagnosis(
                        title: "VPN tunnel is up, but blocked routes fail",
                        explanation: "TUN is active and basic internet may still work, but restricted-service checks fail through the current VPN path.",
                        actions: [
                            "Reconnect VPN and rotate to another node/profile.",
                            "If using Happ/OpenVPN TUN, restart the tunnel service.",
                            "Run Refresh Now and confirm restricted-service probe recovery.",
                        ]
                    ),
                    routeIndicators: routeIndicators,
                    detailLine: routeLine
                )
            }

            return ConnectivityAssessment(
                state: .vpnIssue,
                diagnosis: ConnectivityDiagnosis(
                    title: "VPN tunnel is up but not passing traffic",
                    explanation: "The TUN route is active, but all probes fail. This usually means the VPN tunnel is stale, broken, or upstream is blocked.",
                    actions: [
                        "Reconnect VPN and try a different server/profile.",
                        "Switch ISP and re-check.",
                        "If it persists, verify DNS and proxy settings in the VPN client.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        if snapshot.blockedDirect.ok {
            return ConnectivityAssessment(
                state: .usable,
                diagnosis: ConnectivityDiagnosis(
                    title: "Direct path is open",
                    explanation: "Blocked-service probe succeeds without VPN or proxy. Internet is currently usable directly.",
                    actions: [
                        "Use direct connection while this state remains stable.",
                        "Keep QatVasl running to detect drops quickly.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        if snapshot.blockedProxy.ok {
            return ConnectivityAssessment(
                state: .usable,
                diagnosis: ConnectivityDiagnosis(
                    title: "Proxy path is working",
                    explanation: "Direct blocked-service access fails, but the configured proxy path succeeds.",
                    actions: [
                        "Keep current proxy endpoint active.",
                        "If quality drops, rotate proxy/V2Ray config first.",
                        "Monitor latency for stability before long sessions.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        if snapshot.domestic.ok && snapshot.global.ok {
            return ConnectivityAssessment(
                state: .degraded,
                diagnosis: ConnectivityDiagnosis(
                    title: "General internet works, restricted services fail",
                    explanation: "Domestic and global probes are reachable, but blocked-service probes fail.",
                    actions: [
                        "Rotate VPN/proxy profile to restore blocked-service access.",
                        "Verify proxy host/port and local client status.",
                        "Use Refresh Now after each change.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        if snapshot.domestic.ok && !snapshot.global.ok {
            return ConnectivityAssessment(
                state: .degraded,
                diagnosis: ConnectivityDiagnosis(
                    title: "Domestic-only reachability",
                    explanation: "Domestic probe works but global probe fails, indicating upstream international route problems.",
                    actions: [
                        "Switch ISP first.",
                        "Then reconnect VPN/proxy and re-check.",
                        "Prefer lower timeout presets during unstable periods.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        if proxyEndpointConnected && !snapshot.blockedProxy.ok {
            return ConnectivityAssessment(
                state: .degraded,
                diagnosis: ConnectivityDiagnosis(
                    title: "Proxy endpoint reachable but unusable",
                    explanation: "The proxy port responds, but blocked-service traffic still fails through it.",
                    actions: [
                        "Rotate to a different proxy/V2Ray node.",
                        "Verify protocol type and port match client settings.",
                        "Restart local proxy client and run Refresh Now.",
                    ]
                ),
                routeIndicators: routeIndicators,
                detailLine: routeLine
            )
        }

        return ConnectivityAssessment(
            state: .offline,
            diagnosis: ConnectivityDiagnosis(
                title: "No usable route detected",
                explanation: "Domestic, global, and blocked-service checks all fail from the current direct path.",
                actions: [
                    "Switch ISP and test again.",
                    "Connect VPN or start proxy client.",
                    "If still down, increase timeout and retry.",
                ]
            ),
            routeIndicators: routeIndicators,
            detailLine: routeLine
        )
    }

    private static func makeRouteIndicators(vpnActive: Bool, proxyActive: Bool) -> [RouteIndicator] {
        [
            RouteIndicator(kind: .direct, isActive: !vpnActive && !proxyActive),
            RouteIndicator(kind: .vpn, isActive: vpnActive),
            RouteIndicator(kind: .proxy, isActive: proxyActive),
        ]
    }
}
