import Foundation

/// The Innertube web configuration that search, details and playback need.
/// It is read once from youtube.com, warmed up at launch and shared, so the
/// large page is not downloaded again by every caller.
actor YouTubeWebConfiguration {
    static let shared = YouTubeWebConfiguration()

    struct Values: Sendable {
        let apiKey: String
        let clientVersion: String
        let visitorData: String?
    }

    enum ConfigurationError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "YouTube is temporarily unavailable. Please try again."
        }
    }

    private var cached: Values?
    private var loading: [NetworkRequestPolicy: Task<Values, Error>] = [:]

    func values(policy: NetworkRequestPolicy = .interactive) async throws -> Values {
        try Task.checkCancellation()
        if let cached { return cached }
        if let loading = loading[policy] { return try await loading.value }

        let task = Task { try await Self.fetch(policy: policy) }
        loading[policy] = task
        do {
            let values = try await task.value
            cached = values
            loading[policy] = nil
            return values
        } catch {
            loading[policy] = nil
            throw error
        }
    }

    /// Loads the configuration ahead of the first request. Failures are
    /// ignored; the next request tries again.
    func prewarm() async {
        _ = try? await values(policy: .optional)
    }

    /// Drops the configuration after a failed request, since the key or visitor
    /// data may have rotated. The next request loads it again.
    func invalidate() {
        cached = nil
    }

    private static func fetch(policy: NetworkRequestPolicy) async throws -> Values {
        var request = URLRequest(url: URL(string: "https://www.youtube.com")!)
        policy.apply(to: &request)
        request.timeoutInterval = 15
        // Requests identify as the WEB client, so load the page with a desktop
        // user agent. An iPhone user agent can return the MWEB configuration.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8),
              let apiKey = capture(#"\"INNERTUBE_API_KEY\":\"([^\"]+)\""#, in: html),
              let clientVersion = capture(#"\"INNERTUBE_CLIENT_VERSION\":\"([^\"]+)\""#, in: html)
        else {
            throw ConfigurationError.unavailable
        }

        let visitorData = capture(#"\"VISITOR_DATA\":\"([^\"]+)\""#, in: html)
            ?? capture(#"\"visitorData\":\"([^\"]+)\""#, in: html)
        return Values(apiKey: apiKey, clientVersion: clientVersion, visitorData: visitorData)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
