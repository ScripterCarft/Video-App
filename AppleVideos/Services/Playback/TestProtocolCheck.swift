import Foundation
import os

/// TEST (do not merge): fetches a video's master playlist, its H.264 720p
/// playlist and first segment from the app, once as URLSession chooses and
/// once asking for HTTP/3 first, and reports status and the protocol each
/// request actually used. The download service is refused with 401 while
/// the app is not; YouTube offers HTTP/3, and the computer tests only ever
/// used HTTP/1.1.
enum TestProtocolCheck {
    private final class MetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
        let protocols = OSAllocatedUnfairLock(initialState: [String]())

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            let names = metrics.transactionMetrics.map { $0.networkProtocolName ?? "?" }
            protocols.withLock { $0 = names }
        }
    }

    private static let userAgent = "AppleCoreMedia/1.0.0.24A437 (iPhone; U; CPU OS 27_0 like Mac OS X; en_us)"

    static func run(masterURL: URL) async -> String {
        var lines = ["Protocol check"]
        guard let master = try? await URLSession.shared.data(from: masterURL).0,
              let masterText = String(data: master, encoding: .utf8)
        else { return "Protocol check: master playlist not loaded." }

        let masterLines = masterText.components(separatedBy: "\n")
        let variantURL = masterLines.indices.first { index in
            masterLines[index].hasPrefix("#EXT-X-STREAM-INF")
                && masterLines[index].contains("avc1")
                && masterLines[index].contains("x720")
        }
        .flatMap { masterLines.indices.contains($0 + 1) ? URL(string: masterLines[$0 + 1]) : nil }

        var segmentURL: URL?
        if let variantURL,
           let data = try? await URLSession.shared.data(from: variantURL).0,
           let text = String(data: data, encoding: .utf8) {
            segmentURL = text.components(separatedBy: "\n")
                .first { $0.hasPrefix("https://") }
                .flatMap { URL(string: $0) }
        }

        let targets: [(String, URL?)] = [("master", masterURL), ("720p playlist", variantURL), ("segment", segmentURL)]
        for (label, url) in targets {
            guard let url else {
                lines.append("\(label): not found")
                continue
            }
            for preferHTTP3 in [false, true] {
                lines.append("\(label) · \(preferHTTP3 ? "HTTP/3 first" : "default"): \(await fetch(url, preferHTTP3: preferHTTP3))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Fetches twice in one fresh session, so the second request can use a
    /// protocol the first one learned about (Alt-Svc).
    private static func fetch(_ url: URL, preferHTTP3: Bool) async -> String {
        let collector = MetricsCollector()
        let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var results: [String] = []
        for _ in 0..<2 {
            var request = URLRequest(url: url)
            request.assumesHTTP3Capable = preferHTTP3
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            do {
                let (_, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // Metrics can arrive just after the response.
                try? await Task.sleep(for: .milliseconds(200))
                let used = collector.protocols.withLock { $0.joined(separator: "→") }
                results.append("\(status) via \(used)")
            } catch {
                results.append("error \((error as NSError).code)")
            }
        }
        return results.joined(separator: ", ")
    }
}
