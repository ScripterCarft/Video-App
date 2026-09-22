import Foundation

/// Experimental YouTube implementation of `PlaybackResolving`.
///
/// All Innertube dictionaries, client configuration, format identifiers and
/// response-shape knowledge are intentionally confined to this file. Callers
/// receive only provider-neutral playback models.
actor YouTubeInnertubePlaybackResolver: PlaybackResolving {
    static let shared = YouTubeInnertubePlaybackResolver()

    private struct WebConfiguration: Sendable {
        let apiKey: String
        let clientVersion: String
        let visitorData: String?
    }

    private struct CacheEntry: Sendable {
        let source: ResolvedPlaybackSource
    }

    private let session: URLSession
    private var configuration: WebConfiguration?
    private var cache: [PlaybackRequest: CacheEntry] = [:]
    private var inFlight: [PlaybackRequest: Task<ResolvedPlaybackSource, Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func resolve(_ request: PlaybackRequest) async throws -> ResolvedPlaybackSource {
        guard Self.isValidVideoID(request.videoID) else {
            throw PlaybackResolverError.invalidVideoID
        }

        if let cached = cache[request], cached.source.isFresh() {
            return cached.source
        }
        cache[request] = nil

        if let existing = inFlight[request] {
            return try await existing.value
        }

        let task = Task { try await resolveUncached(request) }
        inFlight[request] = task

        do {
            let source = try await task.value
            inFlight[request] = nil
            cache[request] = CacheEntry(source: source)
            return source
        } catch {
            inFlight[request] = nil
            throw error
        }
    }

    func invalidate(videoID: String? = nil) {
        if let videoID {
            cache = cache.filter { $0.key.videoID != videoID }
        } else {
            cache.removeAll(keepingCapacity: true)
        }
    }

    private func resolveUncached(_ request: PlaybackRequest) async throws -> ResolvedPlaybackSource {
        let configuration = try await webConfiguration()
        guard let endpoint = URL(
            string: "https://www.youtube.com/youtubei/v1/player?key=\(configuration.apiKey)&prettyPrint=false"
        ) else {
            throw PlaybackResolverError.configurationUnavailable
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        urlRequest.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        urlRequest.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        urlRequest.setValue(configuration.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        urlRequest.setValue(request.languageCode, forHTTPHeaderField: "Accept-Language")
        if let visitorData = configuration.visitorData {
            urlRequest.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": configuration.clientVersion,
                    "hl": request.languageCode,
                    "gl": request.regionCode,
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0,
                    "userAgent": Self.webUserAgent
                ]
            ],
            "videoId": request.videoID,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ])

        let (data, response) = try await session.data(for: urlRequest)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw PlaybackResolverError.invalidResponse(statusCode: nil, reason: "Missing HTTP response.")
        }
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard 200..<300 ~= http.statusCode else {
            throw PlaybackResolverError.invalidResponse(
                statusCode: http.statusCode,
                reason: root.flatMap(Self.playabilityDiagnostic)
            )
        }
        guard let root else {
            throw PlaybackResolverError.invalidResponse(
                statusCode: http.statusCode,
                reason: "The response was not valid JSON."
            )
        }

        return try Self.parse(root: root, videoID: request.videoID)
    }

    private func webConfiguration() async throws -> WebConfiguration {
        if let configuration { return configuration }

        var request = URLRequest(url: URL(string: "https://www.youtube.com")!)
        request.timeoutInterval = 15
        request.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let html = String(data: data, encoding: .utf8),
              let apiKey = Self.capture(#"\"INNERTUBE_API_KEY\":\"([^\"]+)\""#, in: html),
              let clientVersion = Self.capture(#"\"INNERTUBE_CLIENT_VERSION\":\"([^\"]+)\""#, in: html)
        else {
            throw PlaybackResolverError.configurationUnavailable
        }

        let visitorData = Self.capture(#"\"VISITOR_DATA\":\"([^\"]+)\""#, in: html)
            ?? Self.capture(#"\"visitorData\":\"([^\"]+)\""#, in: html)
        let value = WebConfiguration(
            apiKey: apiKey,
            clientVersion: clientVersion,
            visitorData: visitorData
        )
        configuration = value
        return value
    }

    private static func parse(root: [String: Any], videoID: String) throws -> ResolvedPlaybackSource {
        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            let reason = playability["reason"] as? String
                ?? text(from: playability["errorScreen"])
            throw PlaybackResolverError.videoUnavailable(status: status, reason: reason)
        }

        if let details = root["videoDetails"] as? [String: Any],
           details["isLiveContent"] as? Bool == true {
            throw PlaybackResolverError.unsupportedLiveContent
        }

        guard let streamingData = root["streamingData"] as? [String: Any] else {
            throw PlaybackResolverError.invalidResponse(
                statusCode: 200,
                reason: Self.playabilityDiagnostic(root) ?? "The response contains no streamingData."
            )
        }

        let progressiveFormats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []
        let allFormats = progressiveFormats + adaptiveFormats
        let now = Date()
        let fallbackExpiration = now.addingTimeInterval(5 * 60)

        var variants: [PlaybackVariant] = []
        if let manifest = streamingData["hlsManifestUrl"] as? String,
           let url = URL(string: manifest) {
            variants.append(PlaybackVariant(
                id: "adaptive-hls",
                url: url,
                transport: .hls,
                qualityLabel: "Auto",
                width: nil,
                height: nil,
                framesPerSecond: nil,
                bitrate: nil,
                mimeType: "application/vnd.apple.mpegurl",
                codecs: nil,
                isHDR: false,
                expiresAt: expirationDate(for: url) ?? fallbackExpiration
            ))
        }

        for format in progressiveFormats {
            guard let variant = progressiveVariant(from: format, fallbackExpiration: fallbackExpiration) else {
                continue
            }
            variants.append(variant)
        }

        variants = uniqueVariants(variants)
        let captions = captionTracks(from: root)
        let nativeLabels = orderedQualityLabels(variants.compactMap(\.qualityLabel).filter { $0 != "Auto" })
        let separateLabels = orderedQualityLabels(adaptiveFormats.compactMap { $0["qualityLabel"] as? String })
        let capabilities = PlaybackCapabilities(
            allQualityLabels: orderedQualityLabels(allFormats.compactMap { $0["qualityLabel"] as? String }),
            nativeQualityLabels: nativeLabels,
            separateTrackQualityLabels: separateLabels,
            hasAdaptiveHLS: variants.contains(where: { $0.transport == .hls }),
            hasCaptions: !captions.isEmpty,
            cipheredFormatCount: allFormats.filter {
                $0["signatureCipher"] != nil || $0["cipher"] != nil
            }.count
        )

        guard !variants.isEmpty else {
            throw PlaybackResolverError.noCompatibleSource(capabilities: capabilities)
        }

        let expiration = variants.map(\.expiresAt).min() ?? fallbackExpiration
        return ResolvedPlaybackSource(
            videoID: videoID,
            variants: variants,
            captions: captions,
            capabilities: capabilities,
            resolvedAt: now,
            expiresAt: expiration
        )
    }

    private static func progressiveVariant(
        from format: [String: Any],
        fallbackExpiration: Date
    ) -> PlaybackVariant? {
        guard let rawURL = format["url"] as? String,
              let url = URL(string: rawURL),
              let mimeType = format["mimeType"] as? String,
              isNativeCombinedMP4(format: format, mimeType: mimeType)
        else { return nil }

        let id: String
        if let value = format["itag"] as? Int {
            id = String(value)
        } else {
            id = url.absoluteString
        }

        return PlaybackVariant(
            id: id,
            url: url,
            transport: .progressive,
            qualityLabel: format["qualityLabel"] as? String,
            width: format["width"] as? Int,
            height: format["height"] as? Int,
            framesPerSecond: format["fps"] as? Int,
            bitrate: format["bitrate"] as? Int,
            mimeType: mimeType,
            codecs: codecs(from: mimeType),
            isHDR: isHDR(format),
            expiresAt: expirationDate(for: url) ?? fallbackExpiration
        )
    }

    private static func isNativeCombinedMP4(format: [String: Any], mimeType: String) -> Bool {
        let normalized = mimeType.lowercased()
        guard normalized.hasPrefix("video/mp4"),
              normalized.contains("avc1"),
              normalized.contains("mp4a")
        else { return false }

        return format["audioQuality"] != nil
            || format["audioChannels"] != nil
            || format["audioSampleRate"] != nil
    }

    private static func captionTracks(from root: [String: Any]) -> [PlaybackCaptionTrack] {
        guard let captions = root["captions"] as? [String: Any],
              let renderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let tracks = renderer["captionTracks"] as? [[String: Any]]
        else { return [] }

        return tracks.compactMap { track in
            guard let baseURL = track["baseUrl"] as? String,
                  let url = URL(string: baseURL),
                  let languageCode = track["languageCode"] as? String
            else { return nil }

            let kind = (track["kind"] as? String)?.lowercased()
            let displayName = text(from: track["name"]) ?? languageCode
            let id = (track["vssId"] as? String) ?? "\(languageCode)-\(kind ?? "standard")"
            return PlaybackCaptionTrack(
                id: id,
                languageCode: languageCode,
                displayName: displayName,
                url: url,
                isAutoGenerated: kind == "asr",
                isTranslatable: track["isTranslatable"] as? Bool == true
            )
        }
    }

    private static func uniqueVariants(_ variants: [PlaybackVariant]) -> [PlaybackVariant] {
        var seen = Set<String>()
        return variants.filter { seen.insert($0.id).inserted }
    }

    private static func orderedQualityLabels(_ labels: [String]) -> [String] {
        Array(Set(labels)).sorted { qualityHeight($0) < qualityHeight($1) }
    }

    private static func qualityHeight(_ label: String) -> Int {
        let digits = label.prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }

    private static func expirationDate(for url: URL) -> Date? {
        guard let rawValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "expire" })?
            .value,
              let timestamp = TimeInterval(rawValue)
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func codecs(from mimeType: String) -> String? {
        guard let marker = mimeType.range(of: "codecs=\"") else { return nil }
        let suffix = mimeType[marker.upperBound...]
        guard let end = suffix.firstIndex(of: "\"") else { return nil }
        return String(suffix[..<end])
    }

    private static func isHDR(_ format: [String: Any]) -> Bool {
        let label = (format["qualityLabel"] as? String)?.uppercased() ?? ""
        if label.contains("HDR") { return true }
        guard let colorInfo = format["colorInfo"] as? [String: Any] else { return false }
        let transfer = (colorInfo["transferCharacteristics"] as? String)?.uppercased() ?? ""
        return transfer.contains("ST2084") || transfer.contains("HLG")
    }

    private static func text(from value: Any?) -> String? {
        if let text = value as? String { return text }
        if let array = value as? [Any] {
            for child in array {
                if let result = text(from: child) { return result }
            }
            return nil
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        if let simpleText = dictionary["simpleText"] as? String { return simpleText }
        if let runs = dictionary["runs"] as? [[String: Any]] {
            let combined = runs.compactMap { $0["text"] as? String }.joined()
            return combined.isEmpty ? nil : combined
        }
        for child in dictionary.values {
            if let result = text(from: child) { return result }
        }
        return nil
    }

    private static func playabilityDiagnostic(_ root: [String: Any]) -> String? {
        guard let playability = root["playabilityStatus"] as? [String: Any] else { return nil }
        let status = playability["status"] as? String
        let reason = playability["reason"] as? String
            ?? text(from: playability["errorScreen"])
        return [status, reason]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    /// Keep the HTTP identity consistent with Innertube's WEB client. An iPhone
    /// user agent can cause YouTube to return MWEB configuration while the
    /// request body identifies itself as WEB.
    private static let webUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)"
}
