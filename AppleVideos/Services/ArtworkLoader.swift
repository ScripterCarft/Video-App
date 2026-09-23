import UIKit

/// Downloads video artwork, trying candidates in order, and keeps
/// display-ready images in memory.
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

        for candidate in candidates {
            guard !Task.isCancelled else { return nil }

            var request = URLRequest(
                url: candidate.url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 20
            )
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            // Large variants are optional. In Low Data Mode the system refuses
            // them and the next, smaller candidate is used instead.
            request.allowsConstrainedNetworkAccess = !candidate.isLarge

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.networkUnavailableReason == .constrained {
                // Low Data Mode refused a large variant: fall back quietly.
                continue
            } catch {
                continue
            }

            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let image = UIImage(data: data),
                  !requiresSixteenByNine || isSixteenByNine(image.size)
            else { continue }

            // Decode (and shrink to the drawn size) in the background, so the
            // main thread never stalls on a large JPEG and memory stays small.
            let prepared = await prepared(image, maxPixelWidth: maxPixelWidth) ?? image
            cache.setObject(prepared, forKey: key)
            return prepared
        }
        return nil
    }

    private static func prepared(_ image: UIImage, maxPixelWidth: CGFloat) async -> UIImage? {
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

    private static func isSixteenByNine(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs((size.width / size.height) - (16.0 / 9.0)) < 0.04
    }
}
