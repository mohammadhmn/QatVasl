import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: MonitorSettings

    @Published var launchAtLoginError: String?
    @Published var detectedISPMessage: String?
    @Published var isDetectingISP = false

    private let defaults: UserDefaults
    private let storageKey = "qatvasl.settings.v1"
    private var persistenceCancellable: AnyCancellable?
    private let ispDetector: ISPDetector

    init(defaults: UserDefaults = .standard, ispDetector: ISPDetector? = nil) {
        self.defaults = defaults
        self.ispDetector = ispDetector ?? ISPDetector()
        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(MonitorSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = .defaults
        }

        var updated = self.settings
        updated.launchAtLogin = LoginItemManager.isEnabled
        self.settings = updated

        persistenceCancellable = $settings
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] settings in
                self?.persist(settings)
            }

        if settings.autoDetectISPOnLaunch {
            Task { [weak self] in
                await self?.detectAndRenameActiveISPProfile()
            }
        }
    }

    func resetToDefaults() {
        var reset = MonitorSettings.defaults
        reset.launchAtLogin = LoginItemManager.isEnabled
        commitSettings(reset)
    }

    func applyPreset(_ preset: SettingsPreset) {
        mutateSettings { updated in
            updated.applyPreset(preset)
        }
    }

    func selectISPProfile(_ id: String) {
        mutateSettings { updated in
            updated.selectProfile(id: id)
        }
    }

    func addISPProfile(named name: String? = nil) {
        mutateSettings { updated in
            updated.addProfile(named: name ?? "New ISP")
        }
    }

    func removeISPProfile(_ id: String) {
        mutateSettings { updated in
            updated.removeProfile(id: id)
        }
    }

    func renameISPProfile(_ id: String, to name: String) {
        mutateSettings { updated in
            updated.renameProfile(id: id, name: name)
        }
    }

    func detectAndRenameActiveISPProfile() async {
        guard !isDetectingISP else { return }

        isDetectingISP = true
        defer { isDetectingISP = false }

        do {
            let result = try await ispDetector.detectCurrentISP()
            renameISPProfile(settings.activeProfileID, to: result.providerName)

            if let ip = result.publicIP, !ip.isEmpty {
                detectedISPMessage = "Detected \(result.providerName) (\(ip)) via \(result.source)."
            } else {
                detectedISPMessage = "Detected \(result.providerName) via \(result.source)."
            }
        } catch {
            detectedISPMessage = "Couldn’t detect ISP automatically. Check connection and retry."
        }
    }

    func updateCriticalService(
        id: String,
        name: String? = nil,
        url: String? = nil,
        enabled: Bool? = nil,
        checkDirect: Bool? = nil,
        checkProxy: Bool? = nil
    ) {
        guard settings.criticalServices.contains(where: { $0.id == id }) else {
            return
        }

        mutateSettings { updated in
            guard let index = updated.criticalServices.firstIndex(where: { $0.id == id }) else {
                return
            }

            if let name {
                updated.criticalServices[index].name = name
            }
            if let url {
                updated.criticalServices[index].url = url
            }
            if let enabled {
                updated.criticalServices[index].enabled = enabled
            }
            if let checkDirect {
                updated.criticalServices[index].checkDirect = checkDirect
            }
            if let checkProxy {
                updated.criticalServices[index].checkProxy = checkProxy
            }
            updated.sanitizeCriticalServices()
        }
    }

    func addCriticalService() {
        mutateSettings { updated in
            updated.criticalServices.append(
                CriticalServiceConfig(name: "New Service", url: "https://")
            )
            updated.sanitizeCriticalServices()
        }
    }

    func removeCriticalService(id: String) {
        mutateSettings { updated in
            updated.criticalServices.removeAll { $0.id == id }
            updated.sanitizeCriticalServices()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchAtLoginError = nil
            mutateSettings { updated in
                updated.launchAtLogin = enabled
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            mutateSettings { updated in
                updated.launchAtLogin = LoginItemManager.isEnabled
            }
        }
    }

    func update(_ mutation: (inout MonitorSettings) -> Void) {
        mutateSettings(mutation)
    }

    private func mutateSettings(_ mutation: (inout MonitorSettings) -> Void) {
        var updated = settings
        mutation(&updated)
        commitSettings(updated)
    }

    private func commitSettings(_ newSettings: MonitorSettings) {
        var synced = newSettings
        synced.syncActiveProfileFromCurrentValues()
        guard synced != settings else {
            return
        }
        settings = synced
    }

    private func persist(_ settings: MonitorSettings) {
        var synced = settings
        synced.syncActiveProfileFromCurrentValues()
        guard let data = try? JSONEncoder().encode(synced) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
