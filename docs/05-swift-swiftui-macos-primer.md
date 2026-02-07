# Swift + SwiftUI + Native macOS Primer (For QatVasl)

This is a practical primer focused on concepts used in this app.

## 1) Swift Basics You Need

### `struct` and `class`

- Use `struct` for value types (copied on assignment), common for models.
- Use `class` for shared mutable state and reference semantics.

In QatVasl:

- Models like `MonitorSettings` are `struct`.
- Stores/monitors like `NetworkMonitor` are `class`.

### `enum`

`enum` is used for finite state machines and typed options.

In QatVasl:

- `ConnectivityState` encodes all possible connectivity states.
- `ProxyType` limits proxy modes (`socks5`, `http`).

### Optionals (`?`)

`String?` means a value can exist or be `nil`.

In QatVasl:

- `vpnClientLabel: String?` is shown only when detectable.

### Async/Await

`async` code runs without blocking UI.

In QatVasl:

- Probe methods are async.
- Background route detection runs in detached utility tasks.

## 2) SwiftUI Basics You Need

### A `View` is a description of UI

Every SwiftUI view has:

```swift
var body: some View { ... }
```

SwiftUI re-renders body when observed state changes.

### State and Data Flow

- `@StateObject`: owns long-lived observable object.
- `@EnvironmentObject`: reads shared observable object from parent.
- `@Published`: marks properties that trigger UI updates when changed.
- `Binding`: two-way value bridge (for forms/controls).

In QatVasl:

- `QatVaslApp` creates `SettingsStore` and `NetworkMonitor` as `@StateObject`.
- `ContentView`, `SettingsView`, `MenuBarContentView` consume them via `@EnvironmentObject`.

### Modifiers

SwiftUI styling and behavior are built by chaining modifiers:

- `.padding()`
- `.foregroundStyle(...)`
- `.buttonStyle(...)`
- `.preferredColorScheme(...)`

## 3) Native macOS App Concepts

### `App` entry point

`QatVaslApp` is the app root (`@main`).

### Scenes

QatVasl defines multiple scenes:

- `WindowGroup`: dashboard window.
- `MenuBarExtra`: menu-bar popover.
- `Settings`: settings window.

### AppKit bridge

Some macOS behavior still needs AppKit:

- Activation policy (`.regular` vs `.accessory`)
- Dock/menu-bar lifecycle behavior
- Window lifecycle observation

QatVasl uses an `NSApplicationDelegate` for this.

## 4) QatVasl Runtime Flow

1. App launches.
2. `NetworkMonitor` starts periodic loop.
3. Every cycle:
   - detect route context (VPN route/proxy/client),
   - run probes (domestic/global/blocked direct/blocked via proxy),
   - evaluate `ConnectivityState`,
   - publish updates to UI,
   - notify on transition when enabled.
4. Menu bar and dashboard update automatically via SwiftUI reactivity.

## 5) Why This App Feels “Native”

- Uses `MenuBarExtra` (not a web wrapper).
- Uses system notifications.
- Uses native settings and windowing behavior.
- Keeps menu bar active even when dashboard is closed.

## 6) Performance Principles Used

- Avoid heavy work on main actor.
- Reuse network sessions.
- Avoid unnecessary state publishes.
- Debounce high-frequency settings changes.
- Keep probes lightweight (`HEAD` requests, no caching).

## 7) Glossary

- **Main actor**: the UI thread context in Swift concurrency.
- **VPN route interface**: virtual interface (often `utun*`) used by VPN/tunnel clients.
- **Proxy endpoint**: local host+port where VPN client exposes proxy.
- **Probe**: network check against one target URL.
- **Transition**: state change from previous connectivity state.

## 8) What to Learn Next

After this primer:

1. Read `docs/06-codebase-walkthrough.md`.
2. Make one small change (example: modify default interval).
3. Build and run to validate understanding.
