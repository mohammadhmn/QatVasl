import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassCard(cornerRadius: 16, tint: .indigo.opacity(0.40)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusPill(state: monitor.displayState)
                    Spacer()
                    if monitor.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(monitor.displayState.detail)
                    .font(.callout.weight(.medium))

                Text(monitor.diagnosis.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                if let snapshot = monitor.lastSnapshot {
                    ForEach(snapshot.allResults) { result in
                        HStack {
                            Label(result.name, systemImage: result.systemImage)
                                .font(.callout)
                            Spacer()
                            Text(result.summary)
                                .font(.caption)
                                .foregroundStyle(result.ok ? .green : .secondary)
                        }
                    }
                } else {
                    Text("Waiting for first probe...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 8) {
                    ForEach(monitor.routeIndicators) { indicator in
                        RouteChip(indicator: indicator)
                    }
                }

                Divider()

                Text("Proxy: \(settingsStore.settings.proxyHost):\(settingsStore.settings.proxyPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(monitor.routeModeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let vpnClientLabel = monitor.vpnClientLabel {
                    Text("Client: \(vpnClientLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Refresh") { monitor.refreshNow() }
                        .buttonStyle(.glass)
                        .disabled(monitor.isChecking)

                    Button("Settings") {
                        presentSettings()
                    }
                    .buttonStyle(.glass)

                    Button("Dashboard") {
                        NSApp.setActivationPolicy(.regular)
                        openWindow(id: "dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func presentSettings() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
