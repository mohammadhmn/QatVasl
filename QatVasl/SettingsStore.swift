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
        settings = reset
    }

    func applyPreset(_ preset: SettingsPreset) {
        var updated = settings
        updated.applyPreset(preset)
        settings = updated
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchAtLoginError = nil

            var updated = settings
            updated.launchAtLogin = enabled
            settings = updated
        } catch {
            launchAtLoginError = error.localizedDescription

            var updated = settings
            updated.launchAtLogin = LoginItemManager.isEnabled
            settings = updated
        }
    }

    private func persist(_ settings: MonitorSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
