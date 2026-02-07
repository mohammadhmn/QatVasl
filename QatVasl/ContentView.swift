import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DashboardSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case probes
    case services
    case timeline
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .probes:
            return "Probes"
        case .services:
            return "Services"
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
        case .services:
            return "square.grid.3x2.fill"
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
        case .services:
            return .cyan
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
                GlassCard(cornerRadius: 14, tint: monitor.displayState.accentColor.opacity(0.45)) {
                    HStack(spacing: 10) {
                        StatusPill(state: monitor.displayState)

                        Spacer()

                        Button {
                            monitor.refreshNow()
                        } label: {
                            ZStack {
                                if monitor.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.callout.weight(.semibold))
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.glass)
                        .disabled(monitor.isChecking)
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
                            diagnosisSection
                            serviceMatrixSection
                            controlsRow
                            probesSection
                        case .probes:
                            statusHero
                            diagnosisSection
                            probesSection
                        case .services:
                            statusHero
                            serviceMatrixSection
                        case .timeline:
                            statusHero
                            diagnosisSection
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
                    if let activeProfile = settingsStore.settings.activeProfile {
                        Text("ISP \(activeProfile.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
        GlassCard(cornerRadius: 24, tint: monitor.displayState.accentColor.opacity(0.45)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    HStack(spacing: 12) {
                        StateGlyph(state: monitor.displayState)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Status")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(monitor.displayState.shortLabel)
                                .font(.title2.weight(.bold))
                        }
                    }

                    Spacer()

                    StatusPill(state: monitor.displayState)
                }

                Text(monitor.displayState.detail)
                    .font(.body.weight(.medium))

                HStack(spacing: 8) {
                    ForEach(monitor.routeIndicators) { indicator in
                        RouteChip(indicator: indicator)
                    }
                }

                if !monitor.isDirectPathClean {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Direct path means no VPN and no PROXY.", systemImage: "info.circle")
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

    private var diagnosisSection: some View {
        GlassCard(cornerRadius: 18, tint: .blue.opacity(0.42)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Why this state?")
                    .font(.headline)

                Text(monitor.diagnosis.title)
                    .font(.callout.weight(.semibold))

                Text(monitor.diagnosis.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !monitor.diagnosis.actions.isEmpty {
                    Text("Fix now")
                        .font(.subheadline.weight(.semibold))

                    ForEach(Array(monitor.diagnosis.actions.enumerated()), id: \.offset) { index, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Button {
                        copyDiagnosisToClipboard()
                    } label: {
                        Label("Copy diagnosis", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.glass)

                    Button {
                        exportDiagnosticsReport()
                    } label: {
                        Label("Export report", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.glass)

                    Button {
                        presentSettings()
                    } label: {
                        Label("Open settings", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.glass)

                    Spacer()
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
                    if let activeProfile = settingsStore.settings.activeProfile {
                        Text("ISP \(activeProfile.name)")
                    }
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

    private var serviceMatrixSection: some View {
        GlassCard(cornerRadius: 18, tint: .cyan.opacity(0.34)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Critical Services")
                    .font(.headline)

                if monitor.criticalServiceResults.isEmpty {
                    Text("No service checks yet. Enable services in Settings and wait for the next refresh.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.criticalServiceResults) { service in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(service.name, systemImage: service.overallOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(service.overallOk ? .green : .orange)
                                    .font(.callout.weight(.semibold))

                                Spacer()

                                Text(service.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 12) {
                                serviceRouteBadge(title: "DIRECT", result: service.direct)
                                serviceRouteBadge(title: "PROXY", result: service.proxy)
                            }
                        }
                        .padding(10)
                        .glassEffect(.regular.tint(.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var transitionsSection: some View {
        GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.40)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("24h Timeline")
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

                let summary = monitor.timelineSummary24h
                if summary.sampleCount == 0 {
                    Text("No 24h data yet. Keep QatVasl running to build timeline history.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        timelineMetric(
                            title: "Uptime",
                            value: "\(summary.uptimePercent)%",
                            subtitle: "Last 24h"
                        )
                        timelineMetric(
                            title: "Drops",
                            value: "\(summary.dropCount)",
                            subtitle: "To offline"
                        )
                        timelineMetric(
                            title: "Avg latency",
                            value: summary.averageLatencyMs.map { "\($0) ms" } ?? "—",
                            subtitle: "Successful probes"
                        )
                        timelineMetric(
                            title: "Recovery",
                            value: summary.meanRecoverySeconds.map { formatDuration(seconds: $0) } ?? "—",
                            subtitle: "Mean time"
                        )
                    }

                    Divider()

                    Text("Latest checks")
                        .font(.subheadline.weight(.semibold))

                    ForEach(monitor.last24hSamples.prefix(8)) { sample in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(sample.state.accentColor)
                                .frame(width: 8, height: 8)

                            Text(sample.state.shortLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(sample.routeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(sample.averageLatencyMs.map { "\($0) ms" } ?? "—")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text("Recent transitions")
                        .font(.subheadline.weight(.semibold))

                    if monitor.transitionHistory.isEmpty {
                        Text("No transitions recorded yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(monitor.transitionHistory.prefix(6)) { entry in
                            HStack {
                                Circle()
                                    .fill(entry.to.accentColor)
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
    }

    private func presentSettings() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copyDiagnosisToClipboard() {
        let snapshotSummary: String
        if let snapshot = monitor.lastSnapshot {
            snapshotSummary = snapshot.allResults
                .map { "\($0.name): \($0.summary)" }
                .joined(separator: "\n")
        } else {
            snapshotSummary = "No probe snapshot yet."
        }

        let payload = """
        Status: \(monitor.displayState.shortLabel)
        \(monitor.routeModeLabel)
        Diagnosis: \(monitor.diagnosis.title)
        \(monitor.diagnosis.explanation)

        Suggested actions:
        \(monitor.diagnosis.actions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        Probes:
        \(snapshotSummary)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    private func exportDiagnosticsReport() {
        let report = monitor.diagnosticsReport(settings: settingsStore.settings)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "qatvasl-diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    @ViewBuilder
    private func timelineMetric(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.weight(.bold))

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let rem = seconds % 60
        if rem == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(rem)s"
    }

    @ViewBuilder
    private func serviceRouteBadge(title: String, result: ServiceRouteProbeResult?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let result {
                Text(result.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.ok ? .green : .secondary)
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
