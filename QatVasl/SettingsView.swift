import Foundation
import SwiftUI

struct SettingsView: View {
    let embedded: Bool

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var monitor: NetworkMonitor

    private var settings: MonitorSettings {
        settingsStore.settings
    }

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        Group {
            if embedded {
                settingsContent
            } else {
                ScrollView {
                    settingsContent
                        .padding(18)
                }
                .frame(minWidth: 640, minHeight: 700)
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !embedded {
                GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.14)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.headline)
                        Text("Configure monitoring, routes, profiles, and alerts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            profilesAndPresetsCard
            monitoringAndTargetsCard
            websiteTargetsCard
            routesAndServicesCard
            notificationsAndSystemCard
            settingsActions
        }
    }

    private var profilesAndPresetsCard: some View {
        GlassCard(cornerRadius: 18, tint: .blue.opacity(0.14)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Profiles & Presets")
                    .font(.headline)

                Text("Use presets for quick tuning, then keep ISP-specific profiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(SettingsPreset.allCases) { preset in
                    Button {
                        settingsStore.applyPreset(preset)
                        monitor.refreshNow()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.callout.weight(.semibold))
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "sparkles")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Picker(
                    "Active profile",
                    selection: Binding(
                        get: { settings.activeProfileID },
                        set: { settingsStore.selectISPProfile($0) }
                    )
                ) {
                    ForEach(settings.ispProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                TextField(
                    "Profile name",
                    text: Binding(
                        get: { settings.activeProfile?.name ?? "" },
                        set: { name in
                            settingsStore.renameISPProfile(settings.activeProfileID, to: name)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        settingsStore.addISPProfile()
                    } label: {
                        Label("Add profile", systemImage: "plus")
                    }
                    .buttonStyle(.glass)

                    Button {
                        settingsStore.removeISPProfile(settings.activeProfileID)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(settings.ispProfiles.count <= 1)

                    Spacer()

                    Text("\(settings.ispProfiles.count) profiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await settingsStore.detectAndRenameActiveISPProfile()
                        }
                    } label: {
                        Label(
                            settingsStore.isDetectingISP ? "Detecting…" : "Auto-detect current ISP",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }
                    .buttonStyle(.glass)
                    .disabled(settingsStore.isDetectingISP)

                    if let detectedISPMessage = settingsStore.detectedISPMessage, !detectedISPMessage.isEmpty {
                        Text(detectedISPMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Toggle("Auto-detect ISP on launch", isOn: binding(\.autoDetectISPOnLaunch))
                    .toggleStyle(.switch)
            }
        }
    }

    private var monitoringAndTargetsCard: some View {
        GlassCard(cornerRadius: 18, tint: .mint.opacity(0.13)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monitoring")
                    .font(.headline)

                HStack {
                    Text("Interval")
                    Spacer()
                    Stepper(value: binding(\.intervalSeconds), in: 10...300, step: 5) {
                        Text("\(Int(settings.intervalSeconds)) sec")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .frame(width: 170)
                }

                HStack {
                    Text("Timeout")
                    Spacer()
                    Stepper(value: binding(\.timeoutSeconds), in: 2...30, step: 1) {
                        Text("\(Int(settings.timeoutSeconds)) sec")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .frame(width: 170)
                }
            }
        }
    }

    private var websiteTargetsCard: some View {
        GlassCard(cornerRadius: 18, tint: .teal.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Probe Websites")
                    .font(.headline)

                Text("Add or edit the websites used for each connectivity condition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                probeWebsiteField(
                    title: "Domestic",
                    subtitle: "Used for local/internal network reachability checks.",
                    systemImage: "house.fill",
                    primaryText: binding(\.domesticURL),
                    extraTargets: settings.domesticExtraURLs,
                    extraKeyPath: \.domesticExtraURLs
                )

                probeWebsiteField(
                    title: "Global",
                    subtitle: "Used for general external internet availability.",
                    systemImage: "globe",
                    primaryText: binding(\.globalURL),
                    extraTargets: settings.globalExtraURLs,
                    extraKeyPath: \.globalExtraURLs
                )

                probeWebsiteField(
                    title: "Blocked Service (Proxy)",
                    subtitle: "Used to verify blocked-service access through proxy route.",
                    systemImage: "lock.shield.fill",
                    primaryText: binding(\.blockedURL),
                    extraTargets: settings.blockedExtraURLs,
                    extraKeyPath: \.blockedExtraURLs
                )

                HStack {
                    Spacer()
                    Button {
                        settingsStore.update { updated in
                            updated.domesticURL = MonitorSettings.defaults.domesticURL
                            updated.domesticExtraURLs = []
                            updated.globalURL = MonitorSettings.defaults.globalURL
                            updated.globalExtraURLs = []
                            updated.blockedURL = MonitorSettings.defaults.blockedURL
                            updated.blockedExtraURLs = []
                        }
                    } label: {
                        Label("Reset website targets", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private var routesAndServicesCard: some View {
        GlassCard(cornerRadius: 18, tint: .cyan.opacity(0.12)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Routes & Critical Services")
                    .font(.headline)

                Toggle("Enable proxy checks", isOn: binding(\.proxyEnabled))

                Picker("Proxy type", selection: binding(\.proxyType)) {
                    ForEach(ProxyType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Proxy host", text: binding(\.proxyHost))
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", value: binding(\.proxyPort), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }

                Divider()

                HStack {
                    Text("Critical services")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        settingsStore.addCriticalService()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                }

                Text("Track key services across direct and proxy paths.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(settings.criticalServices) { service in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(
                                service.name,
                                isOn: Binding(
                                    get: { service.enabled },
                                    set: { settingsStore.updateCriticalService(id: service.id, enabled: $0) }
                                )
                            )
                            .toggleStyle(.switch)

                            Spacer()

                            Button(role: .destructive) {
                                settingsStore.removeCriticalService(id: service.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }

                        TextField(
                            "Service name",
                            text: Binding(
                                get: { service.name },
                                set: { settingsStore.updateCriticalService(id: service.id, name: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        TextField(
                            "Service URL",
                            text: Binding(
                                get: { service.url },
                                set: { settingsStore.updateCriticalService(id: service.id, url: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack {
                            Toggle(
                                "Direct",
                                isOn: Binding(
                                    get: { service.checkDirect },
                                    set: { settingsStore.updateCriticalService(id: service.id, checkDirect: $0) }
                                )
                            )
                            Toggle(
                                "Proxy",
                                isOn: Binding(
                                    get: { service.checkProxy },
                                    set: { settingsStore.updateCriticalService(id: service.id, checkProxy: $0) }
                                )
                            )
                        }
                        .toggleStyle(.switch)
                        .font(.caption)
                    }
                    .padding(10)
                    .glassEffect(.regular.tint(.white.opacity(0.02)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var notificationsAndSystemCard: some View {
        GlassCard(cornerRadius: 18, tint: .purple.opacity(0.13)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications & System")
                    .font(.headline)

                Toggle("Enable notifications", isOn: binding(\.notificationsEnabled))
                Toggle("Notify on recovery", isOn: binding(\.notifyOnRecovery))

                HStack {
                    Text("Alert cooldown")
                    Spacer()
                    Stepper(value: binding(\.notificationCooldownMinutes), in: 0...30, step: 1) {
                        Text("\(Int(settings.notificationCooldownMinutes)) min")
                            .frame(width: 90, alignment: .trailing)
                    }
                    .frame(width: 170)
                }

                Toggle("Quiet hours", isOn: binding(\.quietHoursEnabled))

                if settings.quietHoursEnabled {
                    HStack {
                        Text("From")
                        Spacer()
                        Stepper(value: binding(\.quietHoursStart), in: 0...23, step: 1) {
                            Text(hourLabel(settings.quietHoursStart))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .frame(width: 170)
                    }

                    HStack {
                        Text("To")
                        Spacer()
                        Stepper(value: binding(\.quietHoursEnd), in: 0...23, step: 1) {
                            Text(hourLabel(settings.quietHoursEnd))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .frame(width: 170)
                    }
                }

                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settingsStore.setLaunchAtLogin($0) }
                    )
                )

                if let launchAtLoginError = settingsStore.launchAtLoginError, !launchAtLoginError.isEmpty {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var settingsActions: some View {
        HStack {
            Button("Reset to defaults") {
                settingsStore.resetToDefaults()
                monitor.refreshNow()
            }
            .buttonStyle(.glass)

            Button("Refresh now") {
                monitor.refreshNow()
            }
            .buttonStyle(.glassProminent)

            Spacer()
        }
        .padding(.top, 2)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MonitorSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { updated in
                    updated[keyPath: keyPath] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private func probeWebsiteField(
        title: String,
        subtitle: String,
        systemImage: String,
        primaryText: Binding<String>,
        extraTargets: [String],
        extraKeyPath: WritableKeyPath<MonitorSettings, [String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("Primary website", text: primaryText)
                .textFieldStyle(.roundedBorder)

            if !extraTargets.isEmpty {
                ForEach(Array(extraTargets.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 8) {
                        TextField(
                            "Optional website \(index + 1)",
                            text: extraTargetBinding(extraKeyPath, index: index)
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            removeExtraTarget(extraKeyPath, index: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    addExtraTarget(extraKeyPath)
                } label: {
                    Label("Add optional website", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(10)
        .glassEffect(.regular.tint(.white.opacity(0.02)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func extraTargetBinding(
        _ keyPath: WritableKeyPath<MonitorSettings, [String]>,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let values = settings[keyPath: keyPath]
                guard values.indices.contains(index) else {
                    return ""
                }
                return values[index]
            },
            set: { newValue in
                settingsStore.update { updated in
                    guard updated[keyPath: keyPath].indices.contains(index) else {
                        return
                    }
                    updated[keyPath: keyPath][index] = newValue
                }
            }
        )
    }

    private func addExtraTarget(_ keyPath: WritableKeyPath<MonitorSettings, [String]>) {
        settingsStore.update { updated in
            updated[keyPath: keyPath].append("https://")
        }
    }

    private func removeExtraTarget(_ keyPath: WritableKeyPath<MonitorSettings, [String]>, index: Int) {
        settingsStore.update { updated in
            guard updated[keyPath: keyPath].indices.contains(index) else {
                return
            }
            updated[keyPath: keyPath].remove(at: index)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", max(0, min(hour, 23)))
    }
}
