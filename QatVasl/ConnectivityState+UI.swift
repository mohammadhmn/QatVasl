import SwiftUI

extension ConnectivityState {
    var accentColor: Color {
        switch self {
        case .offline:
            return .red
        case .domesticOnly:
            return .orange
        case .globalLimited:
            return .yellow
        case .vpnOK:
            return .green
        case .vpnOrProxyActive:
            return .blue
        case .openInternet:
            return .mint
        }
    }
}
