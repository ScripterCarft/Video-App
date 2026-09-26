import Foundation

actor YouTubeService {
    static let shared = YouTubeService()

    struct VideoDetails: Sendable {
        let title: String?
        let channelName: String?
        let duration: String?
        let publishedText: String?
        let publishedAt: Date?
        let viewCountText: String?
        let thumbnailURL: URL?
        let description: String?
        let badges: [String]
    }

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

    private var cachedSearches: [String: [Video]] = [:]
    private var cachedDetails: [String: VideoDetails] = [:]
    private var cachedRelated: [String: [Video]] = [:]

    func search(_ query: String, bypassingCache: Bool = false) async throws -> [Video] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let cacheKey = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if !bypassingCache, let cached = cachedSearches[cacheKey] { return cached }

        let configuration = try await YouTubeWebConfiguration.shared.values()
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
            await YouTubeWebConfiguration.shared.invalidate()
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

    func details(for videoID: String) async throws -> VideoDetails {
        if let cached = cachedDetails[videoID] { return cached }

        let configuration = try await YouTubeWebConfiguration.shared.values()
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(configuration.apiKey)&prettyPrint=false") else {
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
            "videoId": videoID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            await YouTubeWebConfiguration.shared.invalidate()
            throw SearchError.invalidResponse
        }

        let videoDetails = root["videoDetails"] as? [String: Any]
        let microformat = root["microformat"] as? [String: Any]
        let playerMicroformat = microformat?["playerMicroformatRenderer"] as? [String: Any]
        let description = (videoDetails?["shortDescription"] as? String)?.collapsedWhitespace
        let details = VideoDetails(
            title: videoDetails?["title"] as? String,
            channelName: videoDetails?["author"] as? String,
            duration: (videoDetails?["lengthSeconds"] as? String)
                .flatMap(Self.durationText),
            publishedText: (playerMicroformat?["publishDate"] as? String)
                .flatMap(Self.relativePublishedText),
            publishedAt: (playerMicroformat?["publishDate"] as? String)
                .flatMap(Self.publishDate),
            viewCountText: (videoDetails?["viewCount"] as? String)
                .flatMap(Self.viewCountText),
            thumbnailURL: Self.thumbnailURL(from: videoDetails?["thumbnail"]),
            description: description,
            badges: Self.playerBadges(from: root)
        )
        cachedDetails[videoID] = details
        return details
    }

    /// The videos YouTube suggests next to `videoID` (its "Up next" list), from
    /// the WEB `next` request its watch page makes. Verified with real
    /// responses: the list arrives as `lockupViewModel` items.
    func relatedVideos(for videoID: String) async throws -> [Video] {
        if let cached = cachedRelated[videoID] { return cached }

        let configuration = try await YouTubeWebConfiguration.shared.values()
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/next?key=\(configuration.apiKey)&prettyPrint=false") else {
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
            "videoId": videoID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            await YouTubeWebConfiguration.shared.invalidate()
            throw SearchError.invalidResponse
        }

        let watchNext = (root["contents"] as? [String: Any])?["twoColumnWatchNextResults"] as? [String: Any]
        let secondary = (watchNext?["secondaryResults"] as? [String: Any])?["secondaryResults"] as? [String: Any]
        let results = secondary?["results"] as? [[String: Any]] ?? []
        var seen: Set<String> = [videoID]
        let videos = results
            .compactMap { $0["lockupViewModel"] as? [String: Any] }
            .compactMap(Self.video(fromLockup:))
            .filter { seen.insert($0.id).inserted }
        cachedRelated[videoID] = videos
        return videos
    }

    /// A video from YouTube's `lockupViewModel`: title, a channel row and a
    /// row with views and age ("4.8M", "1y ago"), the duration badge and the
    /// listed thumbnail.
    private static func video(fromLockup lockup: [String: Any]) -> Video? {
        guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = lockup["contentId"] as? String,
              let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any],
              let title = (metadata["title"] as? [String: Any])?["content"] as? String
        else { return nil }

        let content = (metadata["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any]
        let rows = content?["metadataRows"] as? [[String: Any]] ?? []
        let rowParts: [[String]] = rows.map { row in
            ((row["metadataParts"] as? [[String: Any]]) ?? []).compactMap { part in
                ((part["text"] as? [String: Any])?["content"] as? String)?.collapsedWhitespace
            }
            .filter { !$0.isEmpty }
        }
        let details = rowParts.dropFirst().flatMap { $0 }
        let published = details.first { $0.localizedCaseInsensitiveContains("ago") }
        let views = details.first { $0 != published && $0.first?.isNumber == true }

        let thumbnail = (lockup["contentImage"] as? [String: Any])?["thumbnailViewModel"] as? [String: Any]
        let sources = ((thumbnail?["image"] as? [String: Any])?["sources"] as? [[String: Any]]) ?? []
        let thumbnailURL = (sources.last?["url"] as? String)
            .flatMap { URLComponents(string: $0) }
            .map { components -> URLComponents in
                var components = components
                components.query = nil
                return components
            }?
            .url
        let badgeTexts = ((thumbnail?["overlays"] as? [[String: Any]]) ?? []).flatMap { overlay -> [String] in
            let badges = ((overlay["thumbnailBottomOverlayViewModel"] as? [String: Any])?["badges"] as? [[String: Any]]) ?? []
            return badges.compactMap { ($0["thumbnailBadgeViewModel"] as? [String: Any])?["text"] as? String }
        }
        let duration = badgeTexts.first { $0.contains(":") && $0.allSatisfy { $0.isNumber || $0 == ":" } }

        return .youtube(
            id: id,
            title: title,
            channel: rowParts.first?.first ?? "YouTube",
            duration: duration,
            published: published,
            publishedAt: published.flatMap(approximatePublishDate),
            views: views.map { "\($0) views" },
            thumbnailURL: thumbnailURL
        )
    }

    func refreshedVideo(_ video: Video) async throws -> Video {
        guard video.source == .youtube else { return video }

        let details = try await details(for: video.id)
        return .youtube(
            id: video.id,
            title: details.title ?? video.title,
            channel: details.channelName ?? video.channelName,
            duration: details.duration ?? video.duration,
            published: details.publishedText ?? video.publishedText,
            publishedAt: details.publishedAt ?? video.publishedAt,
            views: details.viewCountText ?? video.viewCountText,
            thumbnailURL: Self.preferredThumbnail(stored: video.thumbnailURL, fresh: details.thumbnailURL),
            description: details.description ?? video.descriptionText,
            badges: details.badges.isEmpty ? video.badges : details.badges
        )
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
        let publishedText = text(from: renderer["publishedTimeText"])

        return .youtube(
            id: id,
            title: title,
            channel: channel,
            duration: text(from: renderer["lengthText"]),
            published: publishedText,
            publishedAt: publishedText.flatMap(approximatePublishDate),
            views: text(from: renderer["viewCountText"]),
            thumbnailURL: thumbnailURL,
            description: text(from: renderer["descriptionSnippet"]),
            badges: badges(from: renderer)
        )
    }

    private static func badges(from renderer: [String: Any]) -> [String]? {
        let badgeSource = renderer["badges"] as? [[String: Any]] ?? []
        let labels = badgeSource.compactMap { badge -> String? in
            guard let metadata = badge["metadataBadgeRenderer"] as? [String: Any] else { return nil }
            return (metadata["label"] as? String) ?? (metadata["tooltip"] as? String)
        }

        var technical: [String] = []
        let joinedLabels = labels.joined(separator: " ").uppercased()
        appendResolution(from: joinedLabels, to: &technical)
        if joinedLabels.contains("HDR") { technical.append("HDR") }
        if joinedLabels.contains("CAPTION")
            || joinedLabels.range(of: #"\bCC\b"#, options: .regularExpression) != nil {
            technical.append("CC")
        }
        if joinedLabels.contains("SDH") || joinedLabels.contains("DEAF AND HARD OF HEARING") {
            technical.append("SDH")
        }
        if joinedLabels.contains("360°") || joinedLabels.contains("360 VIDEO") {
            technical.append("360°")
        }

        let overlayText = textFromTimeStatusOverlay(renderer).uppercased()
        var statuses: [String] = []
        if joinedLabels.contains("PREMIERE") || overlayText.contains("PREMIERE") {
            statuses.append("PREMIERE")
        }
        if renderer["upcomingEventData"] != nil || joinedLabels.contains("UPCOMING") || overlayText.contains("UPCOMING") {
            statuses.append("UPCOMING")
        }
        if !statuses.contains("PREMIERE"),
           !statuses.contains("UPCOMING"),
           (joinedLabels.contains("LIVE NOW") || overlayText == "LIVE") {
            statuses.append("LIVE")
        }

        let values = orderedUnique(technical + statuses)
        return values.isEmpty ? nil : values
    }

    private static func playerBadges(from root: [String: Any]) -> [String] {
        let streaming = root["streamingData"] as? [String: Any]
        let formats = ((streaming?["formats"] as? [[String: Any]]) ?? [])
            + ((streaming?["adaptiveFormats"] as? [[String: Any]]) ?? [])
        let maxHeight = formats.compactMap { $0["height"] as? Int }.max()

        var technical: [String] = []
        if let maxHeight {
            switch maxHeight {
            case 4320...: technical.append("8K")
            case 2160...: technical.append("4K")
            case 720...: technical.append("HD")
            default: technical.append("SD")
            }
        }

        let hasHDR = formats.contains { format in
            let quality = (format["qualityLabel"] as? String)?.uppercased() ?? ""
            let colorInfo = format["colorInfo"] as? [String: Any]
            let transfer = (colorInfo?["transferCharacteristics"] as? String)?.uppercased() ?? ""
            return quality.contains("HDR") || transfer.contains("2084") || transfer.contains("HLG")
        }
        if hasHDR { technical.append("HDR") }

        let captions = root["captions"] as? [String: Any]
        let renderer = captions?["playerCaptionsTracklistRenderer"] as? [String: Any]
        let tracks = renderer?["captionTracks"] as? [[String: Any]] ?? []
        if !tracks.isEmpty { technical.append("CC") }
        let hasConfirmedSDH = tracks.contains { track in
            let name = text(from: track["name"])?.uppercased() ?? ""
            return name.contains("SDH") || name.contains("DEAF AND HARD OF HEARING")
        }
        if hasConfirmedSDH { technical.append("SDH") }

        let is360 = formats.contains { format in
            let projection = (format["projectionType"] as? String)?.uppercased() ?? ""
            return projection.contains("360") || projection.contains("EQUIRECTANGULAR")
        }
        if is360 { technical.append("360°") }

        let videoDetails = root["videoDetails"] as? [String: Any]
        let microformat = root["microformat"] as? [String: Any]
        let playerMicroformat = microformat?["playerMicroformatRenderer"] as? [String: Any]
        let liveDetails = playerMicroformat?["liveBroadcastDetails"] as? [String: Any]
        let playability = root["playabilityStatus"] as? [String: Any]
        let statusText = (
            allStrings(in: playability ?? [:]) + allStrings(in: liveDetails ?? [:])
        ).joined(separator: " ").uppercased()

        var statuses: [String] = []
        if statusText.contains("PREMIERE") {
            statuses.append("PREMIERE")
        }
        if videoDetails?["isUpcoming"] as? Bool == true
            || statusText.contains("UPCOMING") {
            statuses.append("UPCOMING")
        }
        if !statuses.contains("PREMIERE"),
           !statuses.contains("UPCOMING"),
           (videoDetails?["isLive"] as? Bool == true || liveDetails?["isLiveNow"] as? Bool == true) {
            statuses.append("LIVE")
        }

        return orderedUnique(technical + statuses)
    }

    private static func appendResolution(from text: String, to values: inout [String]) {
        if text.contains("8K") { values.append("8K") }
        else if text.contains("4K") { values.append("4K") }
        else if text.range(of: #"\bHD\b"#, options: .regularExpression) != nil
            || text.contains("HIGH DEFINITION") { values.append("HD") }
        else if text.range(of: #"\bSD\b"#, options: .regularExpression) != nil
            || text.contains("STANDARD DEFINITION") { values.append("SD") }
    }

    private static func textFromTimeStatusOverlay(_ renderer: [String: Any]) -> String {
        guard let overlays = renderer["thumbnailOverlays"] as? [[String: Any]] else { return "" }
        return overlays.compactMap { overlay in
            guard let status = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] else { return nil }
            return text(from: status["text"])
        }.joined(separator: " ")
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func allStrings(in value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap(allStrings)
        }
        if let array = value as? [Any] { return array.flatMap(allStrings) }
        return []
    }

    private static func durationText(from secondsText: String) -> String? {
        guard let totalSeconds = Int(secondsText), totalSeconds >= 0 else { return nil }
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func viewCountText(from value: String) -> String? {
        guard let count = Int64(value) else { return nil }
        return "\(count.formatted(.number.notation(.compactName))) views"
    }

    private static func relativePublishedText(from value: String) -> String? {
        guard let date = publishDate(from: value) else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Search results only say "3 days ago" (or "Streamed 3 days ago"). Turn
    /// that into an approximate date so the label keeps advancing; opening the
    /// video's detail screen replaces it with the exact publish date. Returns
    /// nil for other phrasings, which then keep their text.
    private static func approximatePublishDate(from text: String) -> Date? {
        // Long ("3 days ago") and compact ("3d ago", "2mo ago") forms; the
        // compact one comes with YouTube's newer lockup items.
        guard let regex = try? NSRegularExpression(
                pattern: #"(\d+)\s*(second|minute|hour|day|week|month|year|mo|min|s|m|h|d|w|y)s?\s+ago"#,
                options: .caseInsensitive
              ),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Int(text[valueRange])
        else { return nil }

        let component: Calendar.Component
        switch text[unitRange].lowercased() {
        case "second", "s": component = .second
        case "minute", "min", "m": component = .minute
        case "hour", "h": component = .hour
        case "day", "d": component = .day
        case "week", "w": component = .weekOfYear
        case "month", "mo": component = .month
        default: component = .year
        }
        return Calendar.current.date(byAdding: component, value: -value, to: .now)
    }

    /// YouTube sends `publishDate` either as a full timestamp
    /// ("2024-05-01T07:00:00-07:00") or as a plain date ("2024-05-01").
    private static func publishDate(from value: String) -> Date? {
        if let timestamp = try? Date(value, strategy: .iso8601) {
            return timestamp
        }

        let components = value.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: components[0],
                month: components[1],
                day: components[2]
            )
        )
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

    /// Keeps a stored thumbnail URL, whose image stays current through HTTP
    /// revalidation, so refreshing does not reload every card. A 1280 thumbnail
    /// from the details replaces a smaller stored one, which also repairs
    /// entries that earlier stored a small crop although a 1280 size exists.
    private static func preferredThumbnail(stored: URL?, fresh: URL?) -> URL? {
        guard let stored else { return fresh }
        if !Video.isLargeThumbnail(stored), Video.isLargeThumbnail(fresh) {
            return fresh
        }
        return stored
    }

    /// The largest 16:9 thumbnail listed. Artwork is downsampled to its drawn
    /// size, so the largest one is the sharpest without costing memory. (A
    /// 720-pixel limit here picked a 336×188 image from the details response.)
    private static func thumbnailURL(from value: Any?) -> URL? {
        guard let dictionary = value as? [String: Any],
              let thumbnails = dictionary["thumbnails"] as? [[String: Any]]
        else { return nil }

        let candidates = thumbnails.compactMap { thumbnail -> (url: URL, width: Int)? in
            guard let value = thumbnail["url"] as? String,
                  let width = thumbnail["width"] as? Int,
                  let height = thumbnail["height"] as? Int,
                  width > 0,
                  height > 0,
                  abs((Double(width) / Double(height)) - (16.0 / 9.0)) < 0.04,
                  let url = URL(string: value.hasPrefix("//") ? "https:\(value)" : value)
            else { return nil }
            return (url, width)
        }

        return candidates.max(by: { $0.width < $1.width })?.url
    }
}
