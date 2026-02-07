import Combine
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case live
    case services
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .services:
            return "Services"
        case .history:
            return "History"
        case .settings:
            return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .live:
            return "Current health, route, probes, and next actions."
        case .services:
            return "Critical services availability across direct and proxy paths."
        case .history:
            return "Uptime, drops, recovery, and recent transitions."
        case .settings:
            return "Configure monitoring, routes, profiles, and notifications."
        }
    }

    var systemImage: String {
        switch self {
        case .live:
            return "dot.radiowaves.left.and.right"
        case .services:
            return "square.grid.3x2.fill"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .live:
            return .cyan
        case .services:
            return .mint
        case .history:
            return .indigo
        case .settings:
            return .purple
        }
    }

}

@MainActor
final class DashboardNavigationStore: ObservableObject {
    @Published var selectedSection: DashboardSection = .live

    func open(_ section: DashboardSection) {
        selectedSection = section
    }
}
