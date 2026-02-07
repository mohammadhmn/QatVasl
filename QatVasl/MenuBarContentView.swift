import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var navigationStore: DashboardNavigationStore
    @Environment(\.openWindow) private var openWindow

    private var settings: MonitorSettings {
        settingsStore.settings
    }

    private var quickProbes: [ProbeResult] {
        guard let snapshot = monitor.lastSnapshot else {
            return []
        }

        let order: [ProbeKind] = [.domestic, .global, .restrictedViaProxy]
        let map = Dictionary(uniqueKeysWithValues: snapshot.allResults.map { ($0.kind, $0) })
        return order.compactMap { map[$0] }
    }

    var body: some View {
        GlassCard(cornerRadius: 16, tint: .indigo.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    StatusPill(state: monitor.displayState)
                    Spacer()
                    if monitor.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(monitor.diagnosis.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)

                Text("\(monitor.routeModeLabel) · Proxy \(settings.proxyHost):\(settings.proxyPort)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let activeProfile = settings.activeProfile {
                    Text("ISP \(activeProfile.name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                if quickProbes.isEmpty {
                    Text("Running first probe...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(quickProbes) { result in
                        HStack {
                            Label(result.name, systemImage: result.systemImage)
                                .font(.caption)
                            Spacer()
                            Text(result.summary)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(result.ok ? .green : .secondary)
                        }
                    }
                }

                if !monitor.transitionHistory.isEmpty {
                    Divider()

                    Text("Recent")
                        .font(.caption.weight(.semibold))

                    ForEach(monitor.transitionHistory.prefix(2)) { transition in
                        HStack {
                            Circle()
                                .fill(transition.to.accentColor)
                                .frame(width: 7, height: 7)
                            Text(transition.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(transition.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Refresh") {
                        monitor.refreshNow()
                    }
                    .buttonStyle(.glass)
                    .disabled(monitor.isChecking)

                    Button("Dashboard") {
                        openDashboard(section: .live)
                    }
                    .buttonStyle(.glassProminent)

                    Button("Settings") {
                        openDashboard(section: .settings)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(14)
        .frame(width: 342)
    }

    private func openDashboard(section: DashboardSection) {
        navigationStore.open(section)
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
