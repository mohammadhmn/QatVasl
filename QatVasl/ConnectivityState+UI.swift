import SwiftUI

extension ConnectivityState {
    var accentColor: Color {
        switch self {
        case .checking:
            return .blue
        case .offline:
            return .red
        case .degraded:
            return .yellow
        case .usable:
            return .mint
        }
    }
}
