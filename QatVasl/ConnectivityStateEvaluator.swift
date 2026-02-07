import Foundation

enum ConnectivityStateEvaluator {
    static func evaluate(snapshot: ProbeSnapshot, routeContext: RouteContext) -> ConnectivityState {
        if routeContext.vpnActive {
            if snapshot.allResults.contains(where: \.ok) {
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
}
