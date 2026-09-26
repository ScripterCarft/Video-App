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
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    private static var inFlight: [NSString: Task<UIImage?, Never>] = [:]

    /// The image already prepared for these candidates and width, if any.
    static func cachedImage(for candidates: [ArtworkCandidate], maxPixelWidth: CGFloat) -> UIImage? {
        cache.object(forKey: cacheKey(for: candidates, maxPixelWidth: maxPixelWidth))
    }

    /// Returns the first candidate that downloads and decodes, downsampled to
    /// at most `maxPixelWidth`. YouTube's 4:3 sizes are letterboxed, so pass
    /// `requiresSixteenByNine` to skip them in favor of the next candidate.
    static func firstImage(
        from candidates: [ArtworkCandidate],
        requiresSixteenByNine: Bool,
        maxPixelWidth: CGFloat
    ) async -> UIImage? {
        let key = cacheKey(for: candidates, maxPixelWidth: maxPixelWidth)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let running = inFlight[key] {
            return await running.value
        }

        // Unstructured on purpose: the download outlives the view that started it.
        let task = Task {
            let image = await download(
                candidates,
                requiresSixteenByNine: requiresSixteenByNine,
                maxPixelWidth: maxPixelWidth
            )
            if let image {
                cache.setObject(image, forKey: key)
            }
            inFlight[key] = nil
            return image
        }
        inFlight[key] = task
        return await task.value
    }

    /// Loads, decodes and crops off the main actor, so none of it blocks the
    /// interface.
    nonisolated private static func download(
        _ candidates: [ArtworkCandidate],
        requiresSixteenByNine: Bool,
        maxPixelWidth: CGFloat
    ) async -> UIImage? {
        for candidate in candidates {
            var request = URLRequest(url: candidate.url, timeoutInterval: 20)
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            // Large variants are optional. In Low Data Mode the system refuses
            // them and the next, smaller candidate is used instead.
            request.allowsConstrainedNetworkAccess = !candidate.isLarge

            guard let data = await imageData(for: request), let downloaded = UIImage(data: data) else { continue }

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
            return await prepared(image, maxPixelWidth: maxPixelWidth) ?? image
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
                _ = try? await URLSession.shared.data(for: request)
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

    private static func cacheKey(for candidates: [ArtworkCandidate], maxPixelWidth: CGFloat) -> NSString {
        (candidates.map(\.url.absoluteString) + ["\(Int(maxPixelWidth))"])
            .joined(separator: "|") as NSString
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
