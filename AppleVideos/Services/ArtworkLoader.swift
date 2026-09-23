import UIKit

/// Downloads video artwork, trying candidate URLs in order, and keeps
/// display-ready images in memory.
@MainActor
enum ArtworkLoader {
    /// Decoded images by candidate list. Rows that scroll back into view show
    /// their artwork immediately instead of downloading and decoding it again.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    /// The image already prepared for these candidates, if any.
    static func cachedImage(for urls: [URL]) -> UIImage? {
        cache.object(forKey: cacheKey(for: urls))
    }

    /// Returns the first candidate that downloads and decodes. YouTube's 4:3
    /// thumbnail sizes are letterboxed, so pass `requiresSixteenByNine` to
    /// skip them in favor of the next candidate.
    static func firstImage(from urls: [URL], requiresSixteenByNine: Bool) async -> UIImage? {
        if let cached = cachedImage(for: urls) {
            return cached
        }

        for url in urls {
            guard !Task.isCancelled else { return nil }

            var request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 20
            )
            request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let image = UIImage(data: data),
                  !requiresSixteenByNine || isSixteenByNine(image.size)
            else { continue }

            // Decode in the background so the main thread never stalls on a
            // large JPEG while scrolling.
            let prepared = await image.byPreparingForDisplay() ?? image
            cache.setObject(prepared, forKey: cacheKey(for: urls))
            return prepared
        }
        return nil
    }

    private static func cacheKey(for urls: [URL]) -> NSString {
        urls.map(\.absoluteString).joined(separator: "|") as NSString
    }

    private static func isSixteenByNine(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs((size.width / size.height) - (16.0 / 9.0)) < 0.04
    }
}
