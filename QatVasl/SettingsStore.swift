import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum DetectedProfileResolution {
        case selectedExisting(String)
        case createdNew(String)
    }

    @Published var settings: MonitorSettings

    @Published var launchAtLoginError: String?
    @Published var detectedISPMessage: String?
    @Published var isDetectingISP = false

    private let defaults: UserDefaults
    private let storageKey = "qatvasl.settings.v1"
    private var persistenceCancellable: AnyCancellable?
    private let ispDetector: ISPDetector
    private let routeInspector: RouteInspector

    init(
        defaults: UserDefaults = .standard,
        ispDetector: ISPDetector? = nil,
        routeInspector: RouteInspector? = nil
    ) {
        self.defaults = defaults
        self.ispDetector = ispDetector ?? ISPDetector()
        self.routeInspector = routeInspector ?? RouteInspector()
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
                await self?.detectAndSelectISPProfile()
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

    func detectAndSelectISPProfile() async {
        guard !isDetectingISP else { return }

        isDetectingISP = true
        defer { isDetectingISP = false }

        let routeContext = await routeInspector.inspect(cacheTTL: 8, forceRefresh: true)
        if routeContext.vpnActive {
            let clientName = routeContext.vpnClientName ?? "Unknown VPN"
            detectedISPMessage = "VPN is active (\(clientName)). Disconnect VPN to detect direct ISP."
            return
        }

        do {
            let result = try await ispDetector.detectCurrentISP()
            let resolution = upsertDetectedISPProfile(named: result.providerName)

            let actionText: String
            switch resolution {
            case let .selectedExisting(name):
                actionText = "Selected existing profile \(name)"
            case let .createdNew(name):
                actionText = "Created and selected profile \(name)"
            }

            let details: String
            if let ip = result.publicIP, !ip.isEmpty {
                details = "Detected \(result.providerName) (\(ip)) via \(result.source)."
            } else {
                details = "Detected \(result.providerName) via \(result.source)."
            }

            detectedISPMessage = "\(details) \(actionText)."
        } catch {
            detectedISPMessage = "Couldn’t detect ISP automatically. Check connection and retry."
        }
    }

    @available(*, deprecated, message: "Use detectAndSelectISPProfile()")
    func detectAndRenameActiveISPProfile() async {
        await detectAndSelectISPProfile()
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

    private func upsertDetectedISPProfile(named providerName: String) -> DetectedProfileResolution {
        let trimmedProvider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeProvider = trimmedProvider.isEmpty ? "Detected ISP" : trimmedProvider
        let normalizedTarget = normalizedISPName(safeProvider)

        var resolution = DetectedProfileResolution.createdNew(safeProvider)
        mutateSettings { updated in
            if let existingProfile = updated.ispProfiles.first(where: { normalizedISPName($0.name) == normalizedTarget }) {
                updated.selectProfile(id: existingProfile.id)
                resolution = .selectedExisting(existingProfile.name)
                return
            }

            updated.addProfile(named: safeProvider)
            if let activeName = updated.activeProfile?.name {
                resolution = .createdNew(activeName)
            } else {
                resolution = .createdNew(safeProvider)
            }
        }

        return resolution
    }

    private func normalizedISPName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
