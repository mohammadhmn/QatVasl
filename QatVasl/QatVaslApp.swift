import AppKit
import SwiftUI

final class QatVaslAppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeWindowLifecycle()
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicyForVisibleWindows()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeWindowLifecycle() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
        ]

        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateActivationPolicyForVisibleWindows()
            }
        }
    }

    private func updateActivationPolicyForVisibleWindows() {
        let hasRegularAppWindow = NSApp.windows.contains { window in
            window.isVisible && window.level == .normal && window.styleMask.contains(.titled)
        }

        let targetPolicy: NSApplication.ActivationPolicy = hasRegularAppWindow ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }
    }
}

@main
struct QatVaslApp: App {
    @NSApplicationDelegateAdaptor(QatVaslAppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var monitor: NetworkMonitor
    @StateObject private var navigationStore = DashboardNavigationStore()

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _monitor = StateObject(wrappedValue: NetworkMonitor(settingsStore: store))
    }

    var body: some Scene {
        WindowGroup("QatVasl", id: "dashboard") {
            ContentView()
                .environmentObject(settingsStore)
                .environmentObject(monitor)
                .environmentObject(navigationStore)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 700)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(settingsStore)
                .environmentObject(monitor)
                .environmentObject(navigationStore)
                .preferredColorScheme(.dark)
        }
        label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(monitor.displayState.accentColor)
                    .frame(width: 8, height: 8)
                Text(monitor.displayState.compactMenuLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityLabel(monitor.displayState.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
