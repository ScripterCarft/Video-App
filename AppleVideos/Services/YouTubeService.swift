import Foundation

actor YouTubeService {
    static let shared = YouTubeService()

    enum SearchError: LocalizedError {
        case invalidResponse
        case configurationUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "YouTube returned an unreadable response. Please try again."
            case .configurationUnavailable:
                "YouTube search is temporarily unavailable."
            }
        }
    }

    private struct WebConfiguration: Sendable {
        let apiKey: String
        let clientVersion: String
    }

    private var cachedConfiguration: WebConfiguration?
    private var cachedSearches: [String: [Video]] = [:]

    func search(_ query: String) async throws -> [Video] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let cacheKey = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if let cached = cachedSearches[cacheKey] { return cached }

        let configuration = try await webConfiguration()
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/search?key=\(configuration.apiKey)&prettyPrint=false") else {
            throw SearchError.configurationUnavailable
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": configuration.clientVersion,
                    "hl": Locale.current.language.languageCode?.identifier ?? "en",
                    "gl": Locale.current.region?.identifier ?? "US"
                ]
            ],
            "query": normalized
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw SearchError.invalidResponse
        }

        let root = try JSONSerialization.jsonObject(with: data)
        let renderers = Self.collectVideoRenderers(in: root)
        var seen = Set<String>()
        let videos = renderers
            .filter { !Self.isShort($0) }
            .compactMap(Self.video(from:))
            .filter { seen.insert($0.id).inserted }
            .prefix(30)
        let results = Array(videos)
        cachedSearches[cacheKey] = results
        return results
    }

    private func webConfiguration() async throws -> WebConfiguration {
        if let cachedConfiguration { return cachedConfiguration }

        var request = URLRequest(url: URL(string: "https://www.youtube.com")!)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8),
              let apiKey = Self.capture(#"\"INNERTUBE_API_KEY\":\"([^\"]+)\""#, in: html),
              let clientVersion = Self.capture(#"\"INNERTUBE_CLIENT_VERSION\":\"([^\"]+)\""#, in: html)
        else {
            throw SearchError.configurationUnavailable
        }

        let configuration = WebConfiguration(apiKey: apiKey, clientVersion: clientVersion)
        cachedConfiguration = configuration
        return configuration
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func collectVideoRenderers(in value: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["videoRenderer"] as? [String: Any] {
                results.append(renderer)
            }
            for child in dictionary.values {
                results.append(contentsOf: collectVideoRenderers(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                results.append(contentsOf: collectVideoRenderers(in: child))
            }
        }
        return results
    }

    private static func video(from renderer: [String: Any]) -> Video? {
        guard let id = renderer["videoId"] as? String,
              let title = text(from: renderer["title"])
        else { return nil }

        let channel = text(from: renderer["ownerText"])
            ?? text(from: renderer["longBylineText"])
            ?? "YouTube"
        let thumbnailURL = thumbnailURL(from: renderer["thumbnail"])

        return .youtube(
            id: id,
            title: title,
            channel: channel,
            duration: text(from: renderer["lengthText"]),
            published: text(from: renderer["publishedTimeText"]),
            views: text(from: renderer["viewCountText"]),
            thumbnailURL: thumbnailURL,
            description: text(from: renderer["descriptionSnippet"]),
            badges: badges(from: renderer)
        )
    }

    private static func badges(from renderer: [String: Any]) -> [String]? {
        guard let source = renderer["badges"] as? [[String: Any]] else { return nil }
        let allowed = Set(["4K", "HD", "HDR", "CC", "SDH"])
        let values = source.compactMap { badge -> String? in
            guard let metadata = badge["metadataBadgeRenderer"] as? [String: Any] else { return nil }
            let candidate = (metadata["label"] as? String) ?? (metadata["tooltip"] as? String)
            guard let candidate else { return nil }
            let normalized = candidate.uppercased()
            if normalized.contains("4K") { return "4K" }
            if normalized.contains("HDR") { return "HDR" }
            if normalized.contains("SDH") { return "SDH" }
            if normalized.contains("CC") || normalized.contains("CAPTION") { return "CC" }
            if normalized == "HD" { return "HD" }
            return nil
        }
        let unique = Array(NSOrderedSet(array: values)) as? [String] ?? values
        let filtered = unique.filter { allowed.contains($0) }
        return filtered.isEmpty ? nil : filtered
    }

    private static func isShort(_ renderer: [String: Any]) -> Bool {
        if containsShortsMarker(renderer) { return true }

        if let thumbnail = renderer["thumbnail"] as? [String: Any],
           let thumbnails = thumbnail["thumbnails"] as? [[String: Any]],
           let largest = thumbnails.last,
           let width = largest["width"] as? Int,
           let height = largest["height"] as? Int,
           height > width {
            return true
        }

        return false
    }

    private static func containsShortsMarker(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if let text = child as? String {
                    let normalized = text.lowercased()
                    if normalized.contains("/shorts/") ||
                        ((key == "style" || key == "iconType") && normalized.contains("shorts")) {
                        return true
                    }
                }
                if containsShortsMarker(child) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsShortsMarker)
        }
        return false
    }

    private static func text(from value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simpleText = dictionary["simpleText"] as? String { return simpleText }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            let combined = runs.compactMap { $0["text"] as? String }.joined()
            return combined.isEmpty ? nil : combined
        }
        return nil
    }

    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let dictionary = value as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]],
              let url = thumbnails.last?["url"] as? String
        else { return nil }
        return URL(string: url.hasPrefix("//") ? "https:\(url)" : url)
    }
}
