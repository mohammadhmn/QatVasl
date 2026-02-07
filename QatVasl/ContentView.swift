import AppKit
import SwiftUI

private enum DashboardSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case probes
    case timeline
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .probes:
            return "Probes"
        case .timeline:
            return "Timeline"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "square.grid.2x2.fill"
        case .probes:
            return "dot.scope"
        case .timeline:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .cyan
        case .probes:
            return .mint
        case .timeline:
            return .indigo
        case .settings:
            return .purple
        }
    }

}

struct ContentView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @State private var selectedSidebarItem: DashboardSidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                GlassCard(cornerRadius: 18, tint: .indigo) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.icloud.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.cyan)

                            Text("QatVasl")
                                .font(.title3.weight(.bold))
                        }

                        Text("Private network monitor")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                List(DashboardSidebarItem.allCases, selection: $selectedSidebarItem) { item in
                    Label {
                        Text(item.title)
                            .font(.callout.weight(.semibold))
                    } icon: {
                        Image(systemName: item.systemImage)
                            .foregroundStyle(item.tint.opacity(0.72))
                    }
                    .tag(item)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .safeAreaInset(edge: .bottom) {
                GlassCard(cornerRadius: 14, tint: color(for: monitor.currentState).opacity(0.45)) {
                    HStack {
                        StatusPill(state: monitor.currentState)

                        Spacer()

                        Button {
                            monitor.refreshNow()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                        .disabled(monitor.isChecking)

                        if monitor.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(minWidth: 235)
        } detail: {
            ZStack {
                background

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        topStrip

                        switch selectedSidebarItem ?? .overview {
                        case .overview:
                            statusHero
                            controlsRow
                            probesSection
                        case .probes:
                            statusHero
                            probesSection
                        case .timeline:
                            statusHero
                            transitionsSection
                        case .settings:
                            settingsShortcutSection
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.12),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.04, green: 0.06, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 78)
                .offset(x: -300, y: -240)

            Circle()
                .fill(Color.indigo.opacity(0.07))
                .frame(width: 280, height: 280)
                .blur(radius: 74)
                .offset(x: 320, y: -210)
        }
        .ignoresSafeArea()
    }

    private var topStrip: some View {
        GlassCard(cornerRadius: 20, tint: .blue.opacity(0.45)) {
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 3) {
                    Text("QatVasl Dashboard")
                        .font(.headline.weight(.semibold))
                    Text("Route quality and VPN reachability")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Interval \(Int(settingsStore.settings.intervalSeconds))s")
                        .font(.caption.weight(.semibold))
                    Text("Proxy \(settingsStore.settings.proxyHost):\(settingsStore.settings.proxyPort)")
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
                }
            }
        }
    }

    private var statusHero: some View {
        GlassCard(cornerRadius: 24, tint: color(for: monitor.currentState).opacity(0.45)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    HStack(spacing: 12) {
                        StateGlyph(state: monitor.currentState)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Network Status")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(monitor.currentState.shortLabel)
                                .font(.title2.weight(.bold))
                        }
                    }

                    Spacer()

                    StatusPill(state: monitor.currentState)
                }

                Text(monitor.currentState.detail)
                    .font(.body.weight(.medium))

                Text(monitor.currentState.suggestedAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !monitor.isDirectPathClean {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Direct path check paused while TUN/proxy is active.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let vpnClientLabel = monitor.vpnClientLabel {
                            Text("Detected client: \(vpnClientLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    if let lastCheckedAt = monitor.lastCheckedAt {
                        Label(
                            "Last check \(lastCheckedAt.formatted(date: .omitted, time: .standard))",
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label("Waiting for first probe…", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if monitor.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var controlsRow: some View {
        GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.45)) {
            HStack {
                Button {
                    monitor.refreshNow()
                } label: {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
                .disabled(monitor.isChecking)

                Button {
                    selectedSidebarItem = .settings
                    presentSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .buttonStyle(.glass)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Interval \(Int(settingsStore.settings.intervalSeconds))s")
                    Text("Proxy \(settingsStore.settings.proxyHost):\(settingsStore.settings.proxyPort)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var settingsShortcutSection: some View {
        GlassCard(cornerRadius: 18, tint: .purple.opacity(0.45)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("App Settings")
                    .font(.headline)

                Text("Open the full settings panel to edit targets, proxy, notifications, and startup behavior.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        presentSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        monitor.refreshNow()
                    } label: {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(monitor.isChecking)

                    Spacer()
                }
            }
        }
    }

    private var probesSection: some View {
        GlassCard(cornerRadius: 18, tint: .mint.opacity(0.40)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connectivity Probes")
                    .font(.headline)

                if let snapshot = monitor.lastSnapshot {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(snapshot.allResults) { result in
                            ProbeMetricCard(result: result)
                        }
                    }
                } else {
                    Text("First check is running...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transitionsSection: some View {
        GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.40)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Transitions")
                        .font(.headline)

                    Spacer()

                    if !monitor.transitionHistory.isEmpty {
                        Button("Clear") {
                            monitor.clearHistory()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                }

                if monitor.transitionHistory.isEmpty {
                    Text("No transitions recorded yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(monitor.transitionHistory.prefix(6)) { entry in
                        HStack {
                            Circle()
                                .fill(color(for: entry.to))
                                .frame(width: 8, height: 8)

                            Text(entry.label)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func color(for state: ConnectivityState) -> Color {
        switch state {
        case .offline:
            return .red
        case .domesticOnly:
            return .orange
        case .globalLimited:
            return .yellow
        case .vpnOK:
            return .green
        case .tunActive:
            return .blue
        case .openInternet:
            return .mint
        }
    }

    private func presentSettings() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
