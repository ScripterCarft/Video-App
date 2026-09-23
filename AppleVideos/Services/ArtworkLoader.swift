import UIKit

/// Downloads video artwork, trying candidate URLs in order.
@MainActor
enum ArtworkLoader {
    /// Returns the first candidate that downloads and decodes. YouTube's 4:3
    /// thumbnail sizes are letterboxed, so pass `requiresSixteenByNine` to
    /// skip them in favor of the next candidate.
    static func firstImage(from urls: [URL], requiresSixteenByNine: Bool) async -> UIImage? {
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

            return image
        }
        return nil
    }

    private static func isSixteenByNine(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs((size.width / size.height) - (16.0 / 9.0)) < 0.04
    }
}
