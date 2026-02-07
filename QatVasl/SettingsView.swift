import Foundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var monitor: NetworkMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.42)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QatVasl Settings")
                            .font(.headline)
                        Text("Tune probe targets, proxy route, and alert behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(cornerRadius: 18, tint: .blue.opacity(0.42)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Presets")
                            .font(.headline)
                        Text("Apply a tuned profile, then fine-tune below.")
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
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                GlassCard(cornerRadius: 18, tint: .indigo.opacity(0.38)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ISP Profiles")
                            .font(.headline)

                        Picker(
                            "Active profile",
                            selection: Binding(
                                get: { settingsStore.settings.activeProfileID },
                                set: { settingsStore.selectISPProfile($0) }
                            )
                        ) {
                            ForEach(settingsStore.settings.ispProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField(
                            "Profile name",
                            text: Binding(
                                get: { settingsStore.settings.activeProfile?.name ?? "" },
                                set: { newName in
                                    settingsStore.renameISPProfile(settingsStore.settings.activeProfileID, to: newName)
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
                                settingsStore.removeISPProfile(settingsStore.settings.activeProfileID)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .buttonStyle(.glass)
                            .disabled(settingsStore.settings.ispProfiles.count <= 1)

                            Spacer()

                            Text("\(settingsStore.settings.ispProfiles.count) profiles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GlassCard(cornerRadius: 18, tint: .cyan.opacity(0.40)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Monitor")
                            .font(.headline)

                        HStack {
                            Text("Interval")
                            Spacer()
                            Stepper(value: binding(\.intervalSeconds), in: 10...300, step: 5) {
                                Text("\(Int(settingsStore.settings.intervalSeconds)) sec")
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .frame(width: 170)
                        }

                        HStack {
                            Text("Timeout")
                            Spacer()
                            Stepper(value: binding(\.timeoutSeconds), in: 2...30, step: 1) {
                                Text("\(Int(settingsStore.settings.timeoutSeconds)) sec")
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .frame(width: 170)
                        }
                    }
                }

                GlassCard(cornerRadius: 18, tint: .mint.opacity(0.36)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Targets")
                            .font(.headline)
                        TextField("Domestic URL", text: binding(\.domesticURL))
                            .textFieldStyle(.roundedBorder)
                        TextField("Global URL", text: binding(\.globalURL))
                            .textFieldStyle(.roundedBorder)
                        TextField("Blocked URL", text: binding(\.blockedURL))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GlassCard(cornerRadius: 18, tint: .teal.opacity(0.36)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Proxy / VPN")
                            .font(.headline)

                        Toggle("Enable proxy check", isOn: binding(\.proxyEnabled))

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
                    }
                }

                GlassCard(cornerRadius: 18, tint: .purple.opacity(0.40)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notifications & System")
                            .font(.headline)

                        Toggle("Enable notifications", isOn: binding(\.notificationsEnabled))
                        Toggle("Notify on recovery", isOn: binding(\.notifyOnRecovery))

                        HStack {
                            Text("Alert cooldown")
                            Spacer()
                            Stepper(value: binding(\.notificationCooldownMinutes), in: 0...30, step: 1) {
                                Text("\(Int(settingsStore.settings.notificationCooldownMinutes)) min")
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .frame(width: 170)
                        }

                        Toggle("Quiet hours", isOn: binding(\.quietHoursEnabled))

                        if settingsStore.settings.quietHoursEnabled {
                            HStack {
                                Text("From")
                                Spacer()
                                Stepper(value: binding(\.quietHoursStart), in: 0...23, step: 1) {
                                    Text(hourLabel(settingsStore.settings.quietHoursStart))
                                        .frame(width: 90, alignment: .trailing)
                                }
                                .frame(width: 170)
                            }

                            HStack {
                                Text("To")
                                Spacer()
                                Stepper(value: binding(\.quietHoursEnd), in: 0...23, step: 1) {
                                    Text(hourLabel(settingsStore.settings.quietHoursEnd))
                                        .frame(width: 90, alignment: .trailing)
                                }
                                .frame(width: 170)
                            }
                        }

                        Toggle(
                            "Launch at login",
                            isOn: Binding(
                                get: { settingsStore.settings.launchAtLogin },
                                set: { settingsStore.setLaunchAtLogin($0) }
                            )
                        )

                        if let launchAtLoginError = settingsStore.launchAtLoginError, !launchAtLoginError.isEmpty {
                            Text(launchAtLoginError)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

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
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(width: 620)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MonitorSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = settingsStore.settings
                updated[keyPath: keyPath] = newValue
                updated.syncActiveProfileFromCurrentValues()
                settingsStore.settings = updated
            }
        )
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", max(0, min(hour, 23)))
    }
}
