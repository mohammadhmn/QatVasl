import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var monitor: NetworkMonitor
    @EnvironmentObject private var iranPulseMonitor: IranPulseMonitor
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var navigationStore: DashboardNavigationStore

    private var settings: MonitorSettings {
        settingsStore.settings
    }

    private var conciseRouteLabel: String {
        monitor.routeModeLabel.replacingOccurrences(of: "Route: ", with: "")
    }

    private var sidebarSelection: Binding<DashboardSection?> {
        Binding(
            get: { navigationStore.selectedSection },
            set: { section in
                if let section {
                    navigationStore.selectedSection = section
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.18)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.icloud.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text("QatVasl")
                            .font(.headline.weight(.bold))
                    }

                    Text("Network reliability monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            List(DashboardSection.allCases, selection: sidebarSelection) { section in
                Label {
                    Text(section.title)
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section.accentColor.opacity(0.8))
                }
                .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .safeAreaInset(edge: .bottom) {
            GlassCard(cornerRadius: 14, tint: monitor.displayState.accentColor.opacity(0.18)) {
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
        .frame(minWidth: 238)
    }

    private var detail: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pageHeader

                    switch navigationStore.selectedSection {
                    case .live:
                        liveStatusSection
                        diagnosisSection
                        iranPulseSection
                        probesSection
                    case .pulse:
                        pulseInsightsSection
                    case .services:
                        servicesSection
                    case .history:
                        historySection
                    case .settings:
                        settingsSection
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.10),
                Color(red: 0.06, green: 0.07, blue: 0.11),
                Color(red: 0.04, green: 0.05, blue: 0.09),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var pageHeader: some View {
        let selected = navigationStore.selectedSection
        return GlassCard(cornerRadius: 18, tint: .blue.opacity(0.18)) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.title)
                        .font(.headline.weight(.semibold))
                    Text(selected.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(monitor.routeModeLabel)
                        .font(.caption.weight(.semibold))
                    if let activeProfile = settings.activeProfile {
                        Text("ISP \(activeProfile.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let lastCheckedAt = monitor.lastCheckedAt {
                        Text(lastCheckedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var liveStatusSection: some View {
        GlassCard(cornerRadius: 22, tint: monitor.displayState.accentColor.opacity(0.20)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    HStack(spacing: 12) {
                        StateGlyph(state: monitor.displayState)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(monitor.displayState.shortLabel)
                                .font(.title3.weight(.bold))
                        }
                    }

                    Spacer()

                    StatusPill(state: monitor.displayState)
                }

                Text(monitor.displayState.detail)
                    .font(.callout.weight(.medium))

                HStack(spacing: 8) {
                    ForEach(monitor.routeIndicators) { indicator in
                        RouteChip(indicator: indicator)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Context")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Proxy \(settings.proxyHost):\(settings.proxyPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let vpnClientLabel = monitor.vpnClientLabel {
                        Text("VPN client \(vpnClientLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var diagnosisSection: some View {
        GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.16)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnosis")
                    .font(.headline)

                Text(monitor.diagnosis.title)
                    .font(.callout.weight(.semibold))

                Text(monitor.diagnosis.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !monitor.diagnosis.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommended actions")
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
                }

                ViewThatFits {
                    HStack(spacing: 8) {
                        refreshButton
                        copyButton
                        exportButton
                        settingsButton
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            refreshButton
                            copyButton
                        }
                        HStack(spacing: 8) {
                            exportButton
                            settingsButton
                        }
                    }
                }
            }
        }
    }

    private var iranPulseSection: some View {
        let pulse = iranPulseMonitor.snapshot
        return GlassCard(cornerRadius: 18, tint: pulse.severity.accentColor.opacity(0.14)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Iran Internet Pulse")
                            .font(.headline)
                        Text(pulse.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if iranPulseMonitor.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(
                            pulse.severity.title,
                            systemImage: pulse.severity.systemImage
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pulse.severity.accentColor)
                    }
                }

                HStack(spacing: 10) {
                    timelineMetric(
                        title: "Pulse score",
                        value: pulse.score.map { "\($0)/100" } ?? "—",
                        subtitle: "Merged providers"
                    )
                    timelineMetric(
                        title: "Confidence",
                        value: "\(Int((pulse.confidence * 100).rounded()))%",
                        subtitle: "Data quality"
                    )
                    timelineMetric(
                        title: "Updated",
                        value: pulse.lastUpdated.formatted(date: .omitted, time: .shortened),
                        subtitle: "Local time"
                    )
                }

                if pulse.providers.isEmpty {
                    Text("No provider data yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pulse.providers) { provider in
                            HStack(spacing: 8) {
                                Label(provider.source.title, systemImage: provider.severity.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(provider.severity.accentColor)

                                Spacer()

                                if let score = provider.score {
                                    Text("\(score)/100")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(provider.severity.accentColor)
                                } else {
                                    Text("N/A")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Text(providerAgeLabel(provider.capturedAt, stale: provider.stale))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(provider.error ?? provider.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var pulseInsightsSection: some View {
        let pulse = iranPulseMonitor.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            GlassCard(cornerRadius: 18, tint: .orange.opacity(0.14)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current Iran Pulse")
                        .font(.headline)

                    HStack(spacing: 10) {
                        timelineMetric(
                            title: "Pulse score",
                            value: pulse.score.map { "\($0)/100" } ?? "—",
                            subtitle: "Merged result"
                        )
                        timelineMetric(
                            title: "Severity",
                            value: pulse.severity.title,
                            subtitle: "Score band"
                        )
                        timelineMetric(
                            title: "Confidence",
                            value: "\(Int((pulse.confidence * 100).rounded()))%",
                            subtitle: "Data trust level"
                        )
                        timelineMetric(
                            title: "Updated",
                            value: pulse.lastUpdated.formatted(date: .omitted, time: .shortened),
                            subtitle: "Local time"
                        )
                    }

                    Text(pulse.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GlassCard(cornerRadius: 18, tint: .orange.opacity(0.10)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How the merged score is calculated")
                        .font(.headline)

                    Text("1) Provider scores are normalized to 0–100.")
                        .font(.callout)
                    Text("2) Weighted merge: Vanillapp 70%, OONI 30%.")
                        .font(.callout)
                    Text("3) Confidence affects effective provider influence.")
                        .font(.callout)
                    Text("4) Staleness penalty: -8 (some stale), -18 (all stale).")
                        .font(.callout)
                    Text("5) Severity bands: Normal ≥80, Degraded 50–79, Severe <50.")
                        .font(.callout)

                    Divider()

                    Text("What each number means")
                        .font(.subheadline.weight(.semibold))
                    Text("Pulse score: country-level internet health estimate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Confidence: reliability of currently available source data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Updated: last local merge time in QatVasl.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if pulse.providers.isEmpty {
                GlassCard(cornerRadius: 18, tint: .gray.opacity(0.12)) {
                    Text("No provider data yet. Enable providers in Settings → National Monitoring.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(pulse.providers) { provider in
                    GlassCard(cornerRadius: 18, tint: provider.severity.accentColor.opacity(0.10)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(provider.source.title, systemImage: provider.severity.systemImage)
                                    .font(.headline)
                                    .foregroundStyle(provider.severity.accentColor)
                                Spacer()
                                Text(provider.score.map { "\($0)/100" } ?? "N/A")
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text(provider.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(providerFormula(for: provider.source))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                timelineMetric(
                                    title: "Severity",
                                    value: provider.severity.title,
                                    subtitle: provider.stale ? "Stale data" : "Fresh data"
                                )
                                timelineMetric(
                                    title: "Confidence",
                                    value: "\(Int((provider.confidence * 100).rounded()))%",
                                    subtitle: "Provider confidence"
                                )
                                timelineMetric(
                                    title: "Age",
                                    value: providerAgeLabel(provider.capturedAt, stale: provider.stale),
                                    subtitle: "Source freshness"
                                )
                            }

                            if !provider.details.isEmpty {
                                Divider()
                                Text("Current calculation inputs")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(Array(sortedProviderDetails(provider.details).enumerated()), id: \.offset) { _, detail in
                                    HStack {
                                        Text(detail.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(detail.value)
                                            .font(.caption2.weight(.semibold))
                                    }
                                }
                            }

                            if let error = provider.error {
                                Divider()
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private var probesSection: some View {
        GlassCard(cornerRadius: 18, tint: .mint.opacity(0.14)) {
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
                    Text("Running first probe...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var servicesSection: some View {
        GlassCard(cornerRadius: 18, tint: .cyan.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Critical Services")
                        .font(.headline)
                    Spacer()
                    Button {
                        navigationStore.open(.settings)
                    } label: {
                        Label("Manage", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.glass)
                }

                if monitor.criticalServiceResults.isEmpty {
                    Text("No service checks yet. Configure services in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    let total = monitor.criticalServiceResults.count
                    let healthy = monitor.criticalServiceResults.filter(\.overallOk).count
                    HStack(spacing: 10) {
                        timelineMetric(title: "Services up", value: "\(healthy)/\(total)", subtitle: "Current checks")
                        timelineMetric(title: "Route", value: conciseRouteLabel, subtitle: "Active path")
                    }

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
                        .glassEffect(.regular.tint(.white.opacity(0.02)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var historySection: some View {
        GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("History")
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
                    Text("No 24h data yet. Keep QatVasl running.")
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
                        timelineMetric(title: "Uptime", value: "\(summary.uptimePercent)%", subtitle: "Last 24h")
                        timelineMetric(title: "Drops", value: "\(summary.dropCount)", subtitle: "Outages")
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

                    Text("Recent transitions")
                        .font(.subheadline.weight(.semibold))

                    if monitor.transitionHistory.isEmpty {
                        Text("No transitions recorded yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.transitionHistory.prefix(10)) { entry in
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

    private var settingsSection: some View {
        SettingsView(embedded: true)
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
        let report = """
        \(monitor.diagnosticsReport(settings: settings))

        \(iranPulseMonitor.diagnosticsReport())
        """
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "qatvasl-diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func providerAgeLabel(_ date: Date?, stale: Bool) -> String {
        guard let date else {
            return stale ? "stale" : "unknown"
        }
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        return "\(hours)h"
    }

    private func providerFormula(for source: IranPulseSource) -> String {
        switch source {
        case .vanillapp:
            return "Formula: score = ((4 - avg_level)/4 * 100) - (degraded_ratio * 20). Degraded level means status level ≥ 2."
        case .ooni:
            return "Formula: blocked_ratio = min(1, (1.3×confirmed + 1.0×anomaly + 0.9×failure) / sample_count), then score = (1 - blocked_ratio) * 100."
        }
    }

    private func sortedProviderDetails(_ details: [String: String]) -> [(label: String, value: String)] {
        details
            .map { key, value in
                (label: providerDetailLabel(for: key), value: value)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private func providerDetailLabel(for key: String) -> String {
        switch key {
        case "average_latency":
            return "Average latency"
        case "average_level":
            return "Average level"
        case "age_seconds":
            return "Age (seconds)"
        case "blocked_ratio":
            return "Blocked ratio"
        case "captured_at":
            return "Captured at"
        case "datacenters_total":
            return "Datacenters total"
        case "degraded_nodes":
            return "Degraded nodes"
        case "failure_count":
            return "Failure count"
        case "anomaly_count":
            return "Anomaly count"
        case "confirmed_count":
            return "Confirmed blocked count"
        case "sample_count":
            return "Sample count"
        case "status_coverage":
            return "Status coverage"
        case "newest_sample_at":
            return "Newest sample at"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var refreshButton: some View {
        Button {
            monitor.refreshNow()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.glassProminent)
        .disabled(monitor.isChecking)
    }

    private var copyButton: some View {
        Button {
            copyDiagnosisToClipboard()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.glass)
    }

    private var exportButton: some View {
        Button {
            exportDiagnosticsReport()
        } label: {
            Label("Export report", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.glass)
    }

    private var settingsButton: some View {
        Button {
            navigationStore.open(.settings)
        } label: {
            Label("Settings", systemImage: "gearshape.fill")
        }
        .buttonStyle(.glass)
    }

    private func formatDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(remainder)s"
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
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
