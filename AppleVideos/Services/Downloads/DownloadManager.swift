import AVFoundation
import Observation

/// Offline downloads, the way the TV app downloads: a background
/// `AVAssetDownloadURLSession` stores the HLS stream as a package the system
/// manages, and AVPlayer plays it without a network.
///
/// - Only H.264 is downloaded, up to the Download Options quality: the best
///   H.264 variant is chosen from the playlist and pinned with
///   `AVAssetVariantQualifier(variant:)`. VP9 would not play.
/// - Downloads keep running while the app is suspended or terminated; the
///   system relaunches the app to report them.
/// - Only complete downloads are kept. A failed, stopped or interrupted
///   download deletes its partial package.
/// - With Use Mobile Data off, downloads wait for Wi-Fi.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    /// A running download: waiting for a network or loading.
    enum Activity: Equatable {
        case waiting
        case loading(Double)

        var progress: Double {
            if case let .loading(fraction) = self { return fraction }
            return 0
        }
    }

    /// A download that could not be completed, for the alert.
    struct Failure: Identifiable {
        let id = UUID()
        let video: Video
        let message: String
    }

    private struct Record: Codable {
        var video: Video
        /// Relative to the home directory, which changes between installs.
        let path: String
        let downloadedAt: Date
    }

    private struct Pending: Codable {
        let video: Video
        var path: String?
    }

    private enum Keys {
        static let records = "apple-videos.downloads"
        static let pending = "apple-videos.downloads.pending"
    }

    /// Finished downloads, newest first.
    private var records: [Record]
    private(set) var activities: [String: Activity] = [:]
    var failure: Failure?

    /// Completion handlers the system hands over when it relaunches the app
    /// for background download events, by session identifier.
    @ObservationIgnored var backgroundCompletionHandlers: [String: () -> Void] = [:]
    @ObservationIgnored private var pending: [String: Pending]
    @ObservationIgnored private var tasks: [String: AVAssetDownloadTask] = [:]
    @ObservationIgnored private var observations: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var wifiSession: AVAssetDownloadURLSession!
    @ObservationIgnored private var mobileDataSession: AVAssetDownloadURLSession!
    /// The route downloads load from; see `DownloadURLProviding`.
    private let provider: any DownloadURLProviding = DirectDownloadURLProvider()
    private let defaults = UserDefaults.standard

    override private init() {
        records = Self.decode([Record].self, forKey: Keys.records) ?? []
        pending = Self.decode([String: Pending].self, forKey: Keys.pending) ?? [:]
        super.init()

        // Packages can disappear, for example when a backup is restored.
        records.removeAll { !Self.packageExists(atPath: $0.path) }
        persistRecords()

        wifiSession = makeSession(identifier: "com.scriptercarft.AppleVideos.downloads", allowsMobileData: false)
        mobileDataSession = makeSession(
            identifier: "com.scriptercarft.AppleVideos.downloads.mobile",
            allowsMobileData: true
        )
        reconnectRunningTasks()
    }

    private func makeSession(identifier: String, allowsMobileData: Bool) -> AVAssetDownloadURLSession {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.allowsCellularAccess = allowsMobileData
        configuration.allowsExpensiveNetworkAccess = allowsMobileData
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )
    }

    // MARK: - State

    /// Finished downloads, newest first.
    var videos: [Video] {
        records.map(\.video)
    }

    func canDownload(_ video: Video) -> Bool {
        video.source == .youtube
    }

    func isDownloaded(_ video: Video) -> Bool {
        records.contains { $0.video.id == video.id }
    }

    func activity(for video: Video) -> Activity? {
        activities[video.id]
    }

    /// The downloaded package to play instead of streaming.
    func localURL(for video: Video) -> URL? {
        guard let record = records.first(where: { $0.video.id == video.id }) else { return nil }
        return Self.url(forPath: record.path)
    }

    // MARK: - Actions

    func download(_ video: Video) {
        guard canDownload(video), activities[video.id] == nil, !isDownloaded(video) else { return }
        activities[video.id] = .waiting
        let settings = DownloadSettings.current()

        Task {
            do {
                let masterURL = try await provider.masterPlaylistURL(for: video)
                // Mobile data gets the smaller Fast Downloads quality.
                let maximumHeight = NetworkConditions.shared.isExpensive
                    ? DownloadSettings.Quality.fast.maximumHeight
                    : settings.quality.maximumHeight
                let asset = AVURLAsset(url: masterURL)
                guard let qualifier = try await Self.h264Qualifier(for: asset, maximumHeight: maximumHeight) else {
                    throw DownloadError.noCompatibleVariant
                }
                // Stopped while resolving.
                guard activities[video.id] != nil else { return }

                let configuration = AVAssetDownloadConfiguration(asset: asset, title: video.title)
                configuration.primaryContentConfiguration.variantQualifiers = [qualifier]
                let session = settings.useMobileData ? mobileDataSession! : wifiSession!
                let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
                task.taskDescription = video.id
                pending[video.id] = Pending(video: video, path: nil)
                persistPending()
                track(task, videoID: video.id)
                task.resume()
            } catch {
                activities[video.id] = nil
                failure = Failure(video: video, message: error.localizedDescription)
            }
        }
    }

    /// Stops a running download and deletes what it loaded so far.
    func cancel(_ video: Video) {
        if let task = tasks[video.id] {
            // The delegate cleans up once the task reports the cancellation.
            task.cancel()
        } else {
            activities[video.id] = nil
        }
    }

    func remove(_ video: Video) {
        guard let index = records.firstIndex(where: { $0.video.id == video.id }) else { return }
        Self.deletePackage(atPath: records[index].path)
        records.remove(at: index)
        persistRecords()
    }

    func removeAll() {
        for record in records {
            Self.deletePackage(atPath: record.path)
        }
        records = []
        persistRecords()
    }

    /// Deletes the download and loads the video again with a fresh link.
    func renew(_ video: Video) {
        let stored = records.first { $0.video.id == video.id }?.video ?? video
        remove(video)
        download(stored)
    }

    // MARK: - Tasks

    private func track(_ task: AVAssetDownloadTask, videoID: String) {
        tasks[videoID] = task
        observations[videoID] = task.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                DownloadManager.shared.updateProgress(fraction, for: videoID)
            }
        }
        activities[videoID] = .waiting
    }

    private func updateProgress(_ fraction: Double, for videoID: String) {
        guard activities[videoID] != nil else { return }
        activities[videoID] = fraction > 0 ? .loading(fraction) : .waiting
    }

    /// After a relaunch, shows downloads that kept running without the app.
    private func reconnectRunningTasks() {
        Task {
            for session in [wifiSession!, mobileDataSession!] {
                for case let task as AVAssetDownloadTask in await session.allTasks {
                    guard let videoID = task.taskDescription, task.state == .running || task.state == .suspended else {
                        continue
                    }
                    if pending[videoID] == nil {
                        task.cancel()
                    } else {
                        track(task, videoID: videoID)
                    }
                }
            }
        }
    }

    private func finish(videoID: String, error: Error?) {
        tasks[videoID] = nil
        observations[videoID] = nil
        activities[videoID] = nil
        let entry = pending.removeValue(forKey: videoID)
        persistPending()
        guard let entry else { return }

        guard error == nil, let path = entry.path, Self.packageExists(atPath: path) else {
            // Never keep a partial download.
            if let path = entry.path { Self.deletePackage(atPath: path) }
            if let error {
                if (error as NSError).code != NSURLErrorCancelled {
                    failure = Failure(video: entry.video, message: error.localizedDescription)
                }
            } else {
                failure = Failure(video: entry.video, message: "The download couldn't be saved.")
            }
            return
        }

        records.removeAll { $0.video.id == videoID }
        records.insert(Record(video: entry.video, path: path, downloadedAt: .now), at: 0)
        persistRecords()
    }

    // MARK: - Variant choice

    /// Pins the highest H.264 variant up to `maximumHeight`. Without it the
    /// download may pick a VP9 variant, which AVFoundation cannot play.
    nonisolated private static func h264Qualifier(
        for asset: AVURLAsset,
        maximumHeight: CGFloat
    ) async throws -> sending AVAssetVariantQualifier? {
        let variants = try await asset.load(.variants)
        let candidates = variants.filter { variant in
            guard let video = variant.videoAttributes else { return false }
            return video.codecTypes.contains(kCMVideoCodecType_H264)
                && video.presentationSize.height <= maximumHeight
        }
        guard let best = candidates.max(by: { ($0.peakBitRate ?? 0) < ($1.peakBitRate ?? 0) }) else {
            return nil
        }
        return AVAssetVariantQualifier(variant: best)
    }

    // MARK: - Storage

    /// Stores the path from `Library/` on: iOS may report `/private/var/…`
    /// while the home directory reads `/var/…`.
    private static func relativePath(of location: URL) -> String {
        let path = location.path
        guard let range = path.range(of: "/Library/") else { return path }
        return String(path[range.lowerBound...].dropFirst())
    }

    private static func url(forPath path: String) -> URL? {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(path)
    }

    private static func packageExists(atPath path: String) -> Bool {
        url(forPath: path).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    private static func deletePackage(atPath path: String) {
        guard let url = url(forPath: path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Keys.records)
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Keys.pending)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - AVAssetDownloadDelegate

extension DownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        let videoID = assetDownloadTask.taskDescription
        MainActor.assumeIsolated {
            guard let videoID, pending[videoID] != nil else { return }
            pending[videoID]?.path = Self.relativePath(of: location)
            persistPending()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let videoID = task.taskDescription
        let error = error.map { $0 as NSError }
        MainActor.assumeIsolated {
            guard let videoID else { return }
            finish(videoID: videoID, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier
        MainActor.assumeIsolated {
            guard let identifier else { return }
            backgroundCompletionHandlers.removeValue(forKey: identifier)?()
        }
    }
}
