import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: MonitorSettings

    @Published var launchAtLoginError: String?

    private let defaults: UserDefaults
    private let storageKey = "qatvasl.settings.v1"
    private var persistenceCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
    }

    func resetToDefaults() {
        var reset = MonitorSettings.defaults
        reset.launchAtLogin = LoginItemManager.isEnabled
        reset.syncActiveProfileFromCurrentValues()
        settings = reset
    }

    func applyPreset(_ preset: SettingsPreset) {
        var updated = settings
        updated.applyPreset(preset)
        updated.syncActiveProfileFromCurrentValues()
        settings = updated
    }

    func selectISPProfile(_ id: String) {
        var updated = settings
        updated.selectProfile(id: id)
        updated.syncActiveProfileFromCurrentValues()
        settings = updated
    }

    func addISPProfile(named name: String? = nil) {
        var updated = settings
        updated.addProfile(named: name ?? "New ISP")
        updated.syncActiveProfileFromCurrentValues()
        settings = updated
    }

    func removeISPProfile(_ id: String) {
        var updated = settings
        updated.removeProfile(id: id)
        updated.syncActiveProfileFromCurrentValues()
        settings = updated
    }

    func renameISPProfile(_ id: String, to name: String) {
        var updated = settings
        updated.renameProfile(id: id, name: name)
        updated.syncActiveProfileFromCurrentValues()
        settings = updated
    }

    func updateCriticalService(
        id: String,
        name: String? = nil,
        url: String? = nil,
        enabled: Bool? = nil,
        checkDirect: Bool? = nil,
        checkProxy: Bool? = nil
    ) {
        var updated = settings
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
        settings = updated
    }

    func addCriticalService() {
        var updated = settings
        updated.criticalServices.append(
            CriticalServiceConfig(name: "New Service", url: "https://")
        )
        updated.sanitizeCriticalServices()
        settings = updated
    }

    func removeCriticalService(id: String) {
        var updated = settings
        updated.criticalServices.removeAll { $0.id == id }
        updated.sanitizeCriticalServices()
        settings = updated
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchAtLoginError = nil

            var updated = settings
            updated.launchAtLogin = enabled
            updated.syncActiveProfileFromCurrentValues()
            settings = updated
        } catch {
            launchAtLoginError = error.localizedDescription

            var updated = settings
            updated.launchAtLogin = LoginItemManager.isEnabled
            updated.syncActiveProfileFromCurrentValues()
            settings = updated
        }
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
