import AVFoundation
import Observation

/// TEST (do not merge): downloads a video's HLS stream with
/// `AVAssetDownloadURLSession`, the way the TV app downloads, and plays it
/// offline. Answers whether YouTube's streams can be downloaded at all,
/// how large and how fast, before downloads are designed.
@MainActor
@Observable
final class TestDownloads: NSObject {
    enum State {
        case downloading(Double)
        case finished
        case failed
    }

    static let shared = TestDownloads()

    private(set) var states: [String: State] = [:]
    /// Shown as an alert when a download ends.
    var report: String?
    @ObservationIgnored var backgroundCompletion: (() -> Void)?
    @ObservationIgnored private var session: AVAssetDownloadURLSession!
    @ObservationIgnored private var observations: [Int: NSKeyValueObservation] = [:]
    @ObservationIgnored private var tasks: [String: AVAssetDownloadTask] = [:]
    @ObservationIgnored private var currentMode: Mode = .youtube

    private static let pathsKey = "test.downloads.paths"

    override private init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: "videos.downloads.test")
        session = AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
        ipSession = URLSession(
            configuration: .background(withIdentifier: "videos.ipcheck.test"),
            delegate: self,
            delegateQueue: .main
        )
        for videoID in Self.paths.keys where localURL(for: videoID) != nil {
            states[videoID] = .finished
        }
    }

    // MARK: IP check

    @ObservationIgnored private var ipSession: URLSession!
    @ObservationIgnored private var ipCheckLines: [String] = []
    private static let traceURL = URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!

    /// Compares the IP in YouTube's stream link with the IP the app and the
    /// background download service reach the internet with. YouTube binds
    /// stream links to the requesting IP.
    func checkIPs(_ video: Video) {
        Task {
            var lines = ["IP check"]
            if let source = try? await YouTubeInnertubePlaybackResolver.shared.resolve(
                PlaybackRequest(videoID: video.id)
            ), let url = source.variants.first(where: { $0.transport == .hls })?.url {
                lines.append("Stream link IP: \(Self.ipParameter(in: url) ?? "none")")
            }
            let appTrace = (try? await URLSession.shared.data(from: Self.traceURL)).map {
                String(decoding: $0.0, as: UTF8.self)
            }
            lines.append("App: \(Self.summary(ofTrace: appTrace))")
            ipCheckLines = lines
            let task = ipSession.downloadTask(with: Self.traceURL)
            task.taskDescription = "ipcheck"
            task.resume()
        }
    }

    /// Records the request headers of AVPlayer and of the download service.
    func captureHeaders() {
        Task {
            report = await TestHeaderCapture.shared.capture(downloadSession: session)
        }
    }

    private func finishIPCheck(trace: String?, error: String?) {
        var lines = ipCheckLines
        if let error {
            lines.append("Background download service: failed · \(error)")
        } else {
            lines.append("Background download service: \(Self.summary(ofTrace: trace))")
        }
        report = lines.joined(separator: "\n")
    }

    private static func ipParameter(in url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "ip"), index + 1 < components.count else { return nil }
        return components[index + 1]
    }

    /// The IP and whether it arrives through Cloudflare WARP / iCloud Private
    /// Relay style egress, from Cloudflare's trace page.
    private static func summary(ofTrace trace: String?) -> String {
        guard let trace else { return "no answer" }
        let fields = Dictionary(
            trace.split(separator: "\n").compactMap { line -> (String, String)? in
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        return "\(fields["ip"] ?? "?") · warp \(fields["warp"] ?? "?")"
    }

    /// Download packages are stored relative to the home directory, which
    /// changes between app installs.
    private static var paths: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: pathsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: pathsKey) }
    }

    func localURL(for videoID: String) -> URL? {
        guard let path = Self.paths[videoID] else { return nil }
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Three attempts that narrow down the HTTP 401.
    enum Mode: String {
        case youtube = "YouTube"
        case youtubeWithoutSubtitles = "YouTube without subtitles"
        case appleSample = "Apple sample stream"
        case youtubeViaProxy = "YouTube through the app"
    }

    private static let appleSampleURL = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    )!

    func download(_ video: Video, mode: Mode) {
        if case .downloading = states[video.id] { return }
        states[video.id] = .downloading(0)
        currentMode = mode

        Task {
            do {
                let url: URL
                var expiresAt = Date.distantFuture
                if mode == .appleSample {
                    url = Self.appleSampleURL
                } else {
                    let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
                        PlaybackRequest(videoID: video.id)
                    )
                    guard let variant = source.variants.first(where: { $0.transport == .hls }) else {
                        fail(video.id, "No HLS stream for this video.")
                        return
                    }
                    if mode == .youtubeViaProxy {
                        guard let proxied = TestDownloadProxy.shared.proxiedURL(for: variant.url) else {
                            fail(video.id, "Could not start the local proxy.")
                            return
                        }
                        url = proxied
                    } else {
                        url = variant.url
                    }
                    expiresAt = variant.expiresAt
                }
                let asset = AVURLAsset(url: url)
                let configuration = AVAssetDownloadConfiguration(asset: asset, title: video.title)
                if mode == .youtubeWithoutSubtitles {
                    // Audio and video only: deselect the subtitle group.
                    let selection = try await asset.load(.preferredMediaSelection)
                    if let mutable = selection.mutableCopy() as? AVMutableMediaSelection,
                       let legible = try await asset.loadMediaSelectionGroup(for: .legible) {
                        mutable.select(nil, in: legible)
                        configuration.primaryContentConfiguration.mediaSelections = [mutable]
                    }
                }
                // Up to 720p, as "Fast Downloads" would be.
                configuration.primaryContentConfiguration.variantQualifiers = [
                    AVAssetVariantQualifier(
                        predicate: AVAssetVariantQualifier.predicate(
                            forPresentationHeight: 720,
                            operatorType: .lessThanOrEqualTo
                        )
                    )
                ]
                let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
                // Survives a relaunch, unlike an in-memory map.
                task.taskDescription = "\(video.id)|\(Date.now.timeIntervalSince1970)|\(expiresAt.timeIntervalSince1970)"
                let videoID = video.id
                observations[task.taskIdentifier] = task.progress.observe(\.fractionCompleted) { progress, _ in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        TestDownloads.shared.updateProgress(videoID, fraction)
                    }
                }
                tasks[video.id] = task
                task.resume()
            } catch {
                fail(video.id, "Resolving failed: \(error.localizedDescription)")
            }
        }
    }

    func cancel(_ videoID: String) {
        tasks[videoID]?.cancel()
        tasks[videoID] = nil
        states[videoID] = nil
    }

    private func updateProgress(_ videoID: String, _ fraction: Double) {
        if case .downloading = states[videoID] {
            states[videoID] = .downloading(fraction)
        }
    }

    private func fail(_ videoID: String, _ message: String) {
        states[videoID] = .failed
        report = message
    }

    private func finish(description: String?, taskID: Int, error: String?) {
        observations[taskID] = nil
        let parts = (description ?? "").split(separator: "|").map(String.init)
        guard let videoID = parts.first else { return }
        tasks[videoID] = nil
        // Stopped with the stop button.
        if states[videoID] == nil { return }
        let started = parts.count > 1 ? Double(parts[1]).map(Date.init(timeIntervalSince1970:)) : nil
        let expires = parts.count > 2 ? Double(parts[2]).map(Date.init(timeIntervalSince1970:)) : nil

        if let error {
            var progress = ""
            if case let .downloading(fraction) = states[videoID] {
                progress = " at \(Int(fraction * 100)) %"
            }
            let elapsed = started.map { " after \(Int(Date.now.timeIntervalSince($0))) s" } ?? ""
            fail(videoID, "\(currentMode.rawValue): download failed\(progress)\(elapsed).\n\(error)\(proxySummary)")
            return
        }
        guard let url = localURL(for: videoID) else {
            fail(
                videoID,
                "Download finished, but no package was found at \(Self.paths[videoID] ?? "no stored path")."
                    + proxySummary
            )
            return
        }
        states[videoID] = .finished

        let bytes = Self.size(of: url)
        let seconds = started.map { Date.now.timeIntervalSince($0) } ?? 0
        let validity = expires.map { Int($0.timeIntervalSince(started ?? .now) / 60) }
        Task {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            var lines = [
                "\(currentMode.rawValue): download finished.",
                String(format: "Size: %.1f MB", Double(bytes) / 1_000_000),
                "Took: \(Int(seconds)) s",
                "Stream link valid for: \(validity.map { "\($0) min" } ?? "?") after start"
            ]
            if duration > 0 {
                let megabits = Double(bytes) * 8 / duration / 1_000_000
                lines.append(String(format: "Video length: %d s · average %.1f Mbit/s", Int(duration), megabits))
                lines.append(String(format: "≈ %.2f GB/hour", Double(bytes) / duration * 3600 / 1_000_000_000))
            }
            lines.append("Turn on Airplane Mode and press Play to test offline playback.")
            report = lines.joined(separator: "\n") + proxySummary
        }
    }

    /// The proxy's request log, when the download went through the app.
    private var proxySummary: String {
        guard currentMode == .youtubeViaProxy else { return "" }
        let summary = TestDownloadProxy.shared.summary
        TestDownloadProxy.shared.stop()
        return "\n\n" + summary
    }

    /// The error chain with every failing URL: host and path kind (master or
    /// variant playlist, segment, subtitles), to see which request was refused.
    nonisolated static func diagnostic(_ error: Error) -> String {
        var lines: [String] = []
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 5 {
            lines.append("\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)")
            let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
                ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap { URL(string: $0) }
            if let url {
                let path = url.path
                let kind = ["hls_variant", "hls_playlist", "hls_timedtext_playlist", "timedtext", "videoplayback"]
                    .first { path.contains($0) } ?? "other"
                lines.append("   URL: \(url.host ?? "?") · \(kind) · \(String(path.prefix(50)))")
            }
            let otherKeys = nsError.userInfo.keys.filter {
                ![NSUnderlyingErrorKey, NSURLErrorFailingURLErrorKey, NSURLErrorFailingURLStringErrorKey,
                  NSLocalizedDescriptionKey].contains($0)
            }
            for key in otherKeys.sorted() {
                lines.append("   \(key): \(String(describing: nsError.userInfo[key]!).prefix(120))")
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}

extension TestDownloads: AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The file is removed when this returns, so read it now.
        let trace = try? String(contentsOf: location, encoding: .utf8)
        MainActor.assumeIsolated {
            finishIPCheck(trace: trace, error: nil)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        let description = assetDownloadTask.taskDescription
        MainActor.assumeIsolated {
            guard let first = description?.split(separator: "|").first else { return }
            let videoID = String(first)
            // iOS may report /private/var/… while the home directory reads
            // /var/…; store the part from Library/ on, relative to home.
            let full = location.path
            let path = full.range(of: "/Library/").map { String(full[$0.lowerBound...].dropFirst()) } ?? full
            var paths = Self.paths
            paths[videoID] = path
            Self.paths = paths
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let description = task.taskDescription
        let taskID = task.taskIdentifier
        let message = error.map(Self.diagnostic)
        MainActor.assumeIsolated {
            if description == "ipcheck" {
                if let message {
                    finishIPCheck(trace: nil, error: message)
                }
                return
            }
            finish(description: description, taskID: taskID, error: message)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundCompletion?()
            backgroundCompletion = nil
        }
    }
}
