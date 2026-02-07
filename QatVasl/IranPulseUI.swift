import SwiftUI

extension IranPulseSeverity {
    var accentColor: Color {
        switch self {
        case .normal:
            return .mint
        case .degraded:
            return .yellow
        case .severe:
            return .red
        case .unknown:
            return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .normal:
            return "checkmark.seal.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .severe:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}
