import UIKit

/// Downloads video artwork, trying candidates in order, and keeps
/// display-ready images in memory.
///
/// Downloads belong to the loader, not to the view that asked: a card that
/// scrolls out of view does not cancel its download, and a card that asks
/// for the same artwork again joins the download already in flight.
@MainActor
enum ArtworkLoader {
    /// Prepared images by candidate list and target width. Rows that scroll
    /// back into view show their artwork immediately instead of downloading
    /// and decoding it again.
    private static let cache: NSCache<RequestKey, UIImage> = {
        let cache = NSCache<RequestKey, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private final class Flight {
        let id = UUID()
        var task: Task<UIImage?, Never>!
        var keepAlive: Bool
        var prefetchOwners: Set<UUID> = []

        init(keepAlive: Bool) { self.keepAlive = keepAlive }
    }

    struct Prefetch {
        let request: ArtworkRequest
        let owner: UUID
        let flightID: UUID
        let task: Task<UIImage?, Never>
    }

    private static var inFlight: [ArtworkRequest: Flight] = [:]

    /// The image already prepared for these candidates and width, if any.
    static func cachedImage(for request: ArtworkRequest) -> UIImage? {
        cache.object(forKey: RequestKey(request))
    }

    /// Returns the first candidate that downloads and prepares successfully.
    /// The request controls downsampling and removal of YouTube's black bars.
    static func firstImage(for request: ArtworkRequest) async -> UIImage? {
        if let cached = cachedImage(for: request) {
            return cached
        }
        if let running = inFlight[request] {
            // Once a view needs it, keep the shared download even if UIKit
            // cancels its earlier speculative request.
            running.keepAlive = true
            if let image = await running.task.value { return image }
            guard !Task.isCancelled else { return nil }
            if let replacement = inFlight[request], replacement.id != running.id {
                replacement.keepAlive = true
                return await replacement.task.value
            }
            // An optional prefetch can be refused after Low Data Mode turns
            // on. A now-visible image may retry with its smaller candidates.
            return await start(request, keepAlive: true).task.value
        }
        return await start(request, keepAlive: true).task.value
    }

    static func prefetch(_ request: ArtworkRequest) -> Prefetch? {
        guard cachedImage(for: request) == nil else { return nil }
        let running = inFlight[request] ?? start(request, keepAlive: false)
        let owner = UUID()
        running.prefetchOwners.insert(owner)
        return Prefetch(request: request, owner: owner, flightID: running.id, task: running.task)
    }

    static func cancelPrefetch(_ prefetch: Prefetch) {
        guard let running = inFlight[prefetch.request], running.id == prefetch.flightID else { return }
        running.prefetchOwners.remove(prefetch.owner)
        if !running.keepAlive, running.prefetchOwners.isEmpty {
            running.task.cancel()
            inFlight[prefetch.request] = nil
        }
    }

    private static func start(_ request: ArtworkRequest, keepAlive: Bool) -> Flight {
        let flight = Flight(keepAlive: keepAlive)
        let id = flight.id
        // Unstructured on purpose: the download outlives the view that started it.
        flight.task = Task(priority: keepAlive ? .userInitiated : .utility) {
            let image = await download(
                request.candidates,
                requiresSixteenByNine: request.requiresSixteenByNine,
                maxPixelWidth: request.maxPixelWidth,
                isPrefetch: !keepAlive
            )
            guard !Task.isCancelled else { return nil }
            if let image {
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                cache.setObject(image, forKey: RequestKey(request), cost: cost)
            }
            if inFlight[request]?.id == id { inFlight[request] = nil }
            return image
        }
        inFlight[request] = flight
        return flight
    }

    /// Loads, decodes and crops off the main actor, so none of it blocks the
    /// interface.
    @concurrent
    nonisolated private static func download(
        _ candidates: [ArtworkCandidate],
        requiresSixteenByNine: Bool,
        maxPixelWidth: CGFloat,
        isPrefetch: Bool
    ) async -> UIImage? {
        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            var request = URLRequest(url: candidate.url, timeoutInterval: 20)
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            // Large variants are optional. In Low Data Mode the system refuses
            // them and the next, smaller candidate is used instead.
            request.allowsConstrainedNetworkAccess = !isPrefetch && !candidate.isLarge

            guard let data = await imageData(for: request), !Task.isCancelled,
                  let downloaded = UIImage(data: data) else { continue }

            let image: UIImage
            if !requiresSixteenByNine || isSixteenByNine(downloaded.size) {
                image = downloaded
            } else if let cropped = sixteenByNineCenter(of: downloaded) {
                image = cropped
            } else {
                continue
            }

            // Decode (and shrink to the drawn size) in the background, so the
            // main thread never stalls on a large JPEG and memory stays small.
            if let prepared = await prepared(image, maxPixelWidth: maxPixelWidth) {
                return prepared
            }
        }
        return nil
    }

    /// The image data for `request`. A stored copy is used right away, also
    /// after YouTube's two hours (`max-age=7200`), while a normal request
    /// revalidates it in the background with its ETag: an unchanged
    /// thumbnail costs a 304, a changed one is stored and shows next time.
    /// Without a stored copy, the network; failures (including Low Data Mode
    /// refusing a large variant) return nil, and the next candidate is tried.
    nonisolated private static func imageData(for request: URLRequest) async -> Data? {
        if let cached = URLCache.shared.cachedResponse(for: request),
           let response = cached.response as? HTTPURLResponse,
           200..<300 ~= response.statusCode {
            Task.detached(priority: .background) {
                var revalidation = request
                revalidation.allowsConstrainedNetworkAccess = false
                _ = try? await URLSession.shared.data(for: revalidation)
            }
            return cached.data
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode
        else { return nil }
        return data
    }

    nonisolated private static func prepared(_ image: UIImage, maxPixelWidth: CGFloat) async -> UIImage? {
        let width = image.size.width * image.scale
        guard maxPixelWidth > 0, width > maxPixelWidth else {
            return await image.byPreparingForDisplay()
        }
        let height = image.size.height * image.scale * (maxPixelWidth / width)
        return await image.byPreparingThumbnail(ofSize: CGSize(width: maxPixelWidth, height: height))
    }

    private final class RequestKey: NSObject {
        let request: ArtworkRequest

        init(_ request: ArtworkRequest) { self.request = request }
        override var hash: Int { request.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            (object as? RequestKey)?.request == request
        }
    }

    /// The 16:9 band of a 4:3 thumbnail. YouTube's `hqdefault` is 4:3 with
    /// black bars above and below a 16:9 video; its middle band is the frame.
    /// Related videos list only this size.
    nonisolated private static func sixteenByNineCenter(of image: UIImage) -> UIImage? {
        guard image.size.width > 0,
              abs((image.size.width / image.size.height) - (4.0 / 3.0)) < 0.04,
              let cgImage = image.cgImage
        else { return nil }
        let width = CGFloat(cgImage.width)
        let height = (width * 9 / 16).rounded()
        let rect = CGRect(x: 0, y: ((CGFloat(cgImage.height) - height) / 2).rounded(), width: width, height: height)
        return cgImage.cropping(to: rect).map { UIImage(cgImage: $0, scale: image.scale, orientation: image.imageOrientation) }
    }

    nonisolated private static func isSixteenByNine(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs((size.width / size.height) - (16.0 / 9.0)) < 0.04
    }
}
