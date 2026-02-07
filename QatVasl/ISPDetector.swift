import Foundation

struct ISPDetectionResult {
    let providerName: String
    let publicIP: String?
    let source: String
}

struct ISPDetector {
    private struct Endpoint {
        let url: URL
        let source: String
        let providerKeys: [String]
        let ipKeys: [String]
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func detectCurrentISP() async throws -> ISPDetectionResult {
        for endpoint in endpoints {
            do {
                let request = URLRequest(url: endpoint.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200 ... 299).contains(httpResponse.statusCode) else {
                    continue
                }

                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let provider = firstValue(in: json, keys: endpoint.providerKeys)
                else {
                    continue
                }

                let cleanProvider = sanitizeProvider(provider)
                guard !cleanProvider.isEmpty else {
                    continue
                }

                return ISPDetectionResult(
                    providerName: cleanProvider,
                    publicIP: firstValue(in: json, keys: endpoint.ipKeys),
                    source: endpoint.source
                )
            } catch {
                continue
            }
        }

        throw URLError(.cannotFindHost)
    }

    private func firstValue(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func sanitizeProvider(_ provider: String) -> String {
        var value = provider
            .replacingOccurrences(of: "AS[0-9]+\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if value.lowercased().hasPrefix("as") {
            value = value.replacingOccurrences(of: "^as[0-9]+\\s*", with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normalized = value.lowercased()
        let aliases: [(match: String, alias: String)] = [
            ("mobile communication company of iran", "MCI"),
            ("mci", "MCI"),
            ("iran telecommunication company", "Mokhaberat"),
            ("telecommunication company of iran", "Mokhaberat"),
            ("mokhaberat", "Mokhaberat"),
            ("irancell", "Irancell"),
            ("mtn irancell", "Irancell"),
            ("rightel", "Rightel"),
            ("shatel", "Shatel"),
            ("pars online", "Pars Online"),
            ("parsonline", "Pars Online"),
            ("hiweb", "HiWeb"),
            ("hi-web", "HiWeb"),
            ("asiatech", "Asiatech"),
            ("fanava", "Fanava"),
            ("respina", "Respina"),
            ("pishgaman", "Pishgaman"),
        ]

        if let hit = aliases.first(where: { normalized.contains($0.match) }) {
            return hit.alias
        }

        return value
    }

    private var endpoints: [Endpoint] {
        [
            Endpoint(
                url: URL(string: "https://ipapi.co/json/")!,
                source: "ipapi.co",
                providerKeys: ["org", "asn_org", "asn"],
                ipKeys: ["ip", "query"]
            ),
            Endpoint(
                url: URL(string: "https://ipinfo.io/json")!,
                source: "ipinfo.io",
                providerKeys: ["org", "company", "asn"],
                ipKeys: ["ip"]
            ),
            Endpoint(
                url: URL(string: "https://ifconfig.co/json")!,
                source: "ifconfig.co",
                providerKeys: ["asn_org", "organization", "org"],
                ipKeys: ["ip"]
            ),
        ]
    }
}
