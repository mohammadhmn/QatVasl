import SwiftUI
import WebKit

enum ExternalRadarSite: String, CaseIterable, Identifiable {
    case cloudflare
    case arvan
    case vanillapp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloudflare:
            return "Cloudflare"
        case .arvan:
            return "Arvan"
        case .vanillapp:
            return "Vanillapp"
        }
    }

    var url: URL {
        switch self {
        case .cloudflare:
            return URL(string: "https://radar.cloudflare.com/")!
        case .arvan:
            return URL(string: "https://radar.arvancloud.ir/")!
        case .vanillapp:
            return URL(string: "https://radar.vanillapp.ir/")!
        }
    }

    var helpText: String {
        switch self {
        case .cloudflare:
            return "Cloudflare Radar is embedded as a live website view. Challenge pages may appear."
        case .arvan:
            return "Arvan Radar is embedded as a live website view. Challenge pages or redirects may appear."
        case .vanillapp:
            return "Vanillapp Radar is embedded as a live website view for manual cross-checking."
        }
    }
}

struct ExternalRadarPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSite: ExternalRadarSite = .cloudflare
    @State private var reloadToken = UUID()
    @State private var statusMessage = "Loading page…"
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerCard
            controlsCard
            webContainer
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(minWidth: 980, minHeight: 720, alignment: .topLeading)
        .preferredColorScheme(.dark)
    }

    private var headerCard: some View {
        GlassCard(cornerRadius: 14, tint: .orange.opacity(0.10)) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("External Radar Panel")
                        .font(.headline)
                    Text("Live website view for Cloudflare, Arvan, and Vanillapp (no API coupling).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var controlsCard: some View {
        GlassCard(cornerRadius: 14, tint: .cyan.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Radar site", selection: $selectedSite) {
                        ForEach(ExternalRadarSite.allCases) { site in
                            Text(site.title).tag(site)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    Spacer(minLength: 8)

                    Button {
                        reloadToken = UUID()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)

                    Button {
                        NSWorkspace.shared.open(selectedSite.url)
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.glassProminent)
                }

                Text(selectedSite.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var webContainer: some View {
        GlassCard(cornerRadius: 14, tint: .gray.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 10) {
                RadarWebView(
                    url: selectedSite.url,
                    reloadToken: reloadToken,
                    statusMessage: $statusMessage,
                    lastError: $lastError
                )
                .frame(maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
                )

                HStack(spacing: 10) {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text(selectedSite.url.host() ?? selectedSite.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let lastError, !lastError.isEmpty {
                    Text("WebView notice: \(lastError)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct RadarWebView: NSViewRepresentable {
    let url: URL
    let reloadToken: UUID
    @Binding var statusMessage: String
    @Binding var lastError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        webView.load(request)
        context.coordinator.lastLoadedURL = url
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastReloadToken != reloadToken {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView.load(request)
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.lastLoadedURL = url
            return
        }

        if context.coordinator.lastLoadedURL != url {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView.load(request)
            context.coordinator.lastLoadedURL = url
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RadarWebView
        var lastLoadedURL: URL?
        var lastReloadToken: UUID?

        init(parent: RadarWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            parent.statusMessage = "Loading…"
            parent.lastError = nil
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            if let url = webView.url?.absoluteString, !url.isEmpty {
                parent.statusMessage = "Loaded \(url)"
            } else {
                parent.statusMessage = "Loaded."
            }
        }

        func webView(
            _: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError error: Error
        ) {
            parent.statusMessage = "Load failed."
            parent.lastError = error.localizedDescription
        }

        func webView(
            _: WKWebView,
            didFail _: WKNavigation!,
            withError error: Error
        ) {
            parent.statusMessage = "Navigation failed."
            parent.lastError = error.localizedDescription
        }
    }
}
