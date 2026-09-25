import Foundation
import Network

/// TEST (do not merge): a local pass-through server on 127.0.0.1. The
/// download service requests every playlist and segment from here; the app
/// fetches it from YouTube with its own URLSession (the connection that
/// streams fine) and passes it on. Playlists are rewritten so every URL
/// in them goes through the proxy too. Each request is logged with
/// YouTube's status code.
@MainActor
final class TestDownloadProxy {
    static let shared = TestDownloadProxy()

    nonisolated private static let port: NWEndpoint.Port = 8090
    private var listener: NWListener?
    private(set) var log: [String] = []
    private var counts: [String: Int] = [:]

    /// Starts the server if needed and returns the proxied URL for `url`.
    /// When true, the proxy serves only the master playlist (without VP9) and
    /// leaves every other request to go to YouTube directly.
    var servesMasterOnly = false

    func proxiedURL(for url: URL) -> URL? {
        if listener == nil {
            log = []
            counts = [:]
            failures = []
            retryLog = []
            startDate = .now
            guard let listener = try? NWListener(using: .tcp, on: Self.port) else { return nil }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                Self.receive(on: connection, buffer: Data())
            }
            listener.start(queue: .main)
            self.listener = listener
        }
        return Self.proxied(url)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The first lines of the log plus a count per status and request kind.
    var summary: String {
        let totals = counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return (["Retried after 401 (first 8):"] + retryLog.prefix(8)
            + ["Still refused (first 3):"] + failures.prefix(3) + ["Totals:"] + totals)
            .joined(separator: "\n")
    }

    private var failures: [String] = []
    private var retryLog: [String] = []
    private var startDate = Date.now

    // MARK: URLs

    nonisolated private static func proxied(_ url: URL) -> URL? {
        let token = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        return URL(string: "http://127.0.0.1:\(port)/p/\(token)/\(name)")
    }

    nonisolated private static func original(fromPath path: String) -> URL? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "p" else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return URL(string: String(decoding: data, as: UTF8.self))
    }

    /// A value from YouTube's path-style parameters (`/itag/311/`).
    nonisolated private static func pathValue(_ name: String, in url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: name), index + 1 < components.count else { return nil }
        return components[index + 1]
    }

    nonisolated private static func kind(of url: URL) -> String {
        let path = url.path
        for kind in ["hls_variant", "hls_playlist", "hls_timedtext_playlist", "timedtext", "videoplayback"]
        where path.contains(kind) {
            return kind
        }
        return url.host ?? "other"
    }

    /// Points every absolute URL in a playlist at the proxy. With
    /// `keepingURLs`, only the VP9 variants are removed and every other URL
    /// stays pointed at YouTube, so the download service fetches it directly.
    nonisolated private static func rewritePlaylist(_ text: String, keepingURLs: Bool = false) -> String {
        // Drop VP9 variants (and the URL line after each), which AVFoundation
        // cannot play but a download would otherwise pick.
        var lines: [String] = []
        var skipNext = false
        for line in text.components(separatedBy: "\n") {
            if skipNext {
                skipNext = false
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF"), line.contains("vp09") {
                skipNext = true
                continue
            }
            lines.append(line)
        }
        if keepingURLs {
            return lines.joined(separator: "\n")
        }
        return lines.map { line in
            if line.hasPrefix("https://") || line.hasPrefix("http://") {
                return URL(string: line.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap(proxied)?.absoluteString ?? line
            }
            guard line.hasPrefix("#"), line.contains("URI=\"http") else { return line }
            let pieces = line.components(separatedBy: "URI=\"")
            var result = pieces[0]
            for piece in pieces.dropFirst() {
                guard let quote = piece.firstIndex(of: "\"") else {
                    result += "URI=\"" + piece
                    continue
                }
                let value = String(piece[..<quote])
                let replacement = URL(string: value).flatMap(proxied)?.absoluteString ?? value
                result += "URI=\"" + replacement + piece[quote...]
            }
            return result
        }
        .joined(separator: "\n")
    }

    // MARK: Server

    nonisolated private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            let text = String(decoding: buffer, as: UTF8.self)
            guard text.contains("\r\n\r\n") || isComplete || error != nil else {
                receive(on: connection, buffer: buffer)
                return
            }
            let lines = text.components(separatedBy: "\r\n")
            let requestParts = (lines.first ?? "").split(separator: " ")
            let path = requestParts.count > 1 ? String(requestParts[1]) : ""
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            Task { @MainActor in
                await TestDownloadProxy.shared.respond(to: path, headers: headers, on: connection)
            }
        }
    }

    private func respond(to path: String, headers: [String: String], on connection: NWConnection) async {
        guard let url = Self.original(fromPath: path) else {
            send(status: 400, reason: "Bad Request", headers: [:], body: Data(), on: connection)
            return
        }
        var request = URLRequest(url: url)
        request.setValue(headers["user-agent"], forHTTPHeaderField: "User-Agent")
        if let range = headers["range"] {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        let kind = Self.kind(of: url)
        do {
            let firstTry = Date.now
            var (data, response) = try await URLSession.shared.data(for: request)
            // On 401, wait and try again for up to 60 s, to learn whether YouTube
            // limits how far ahead media may be fetched and releases it later.
            var retries = 0
            while (response as? HTTPURLResponse)?.statusCode == 401, retries < 30 {
                retries += 1
                try await Task.sleep(for: .seconds(2))
                (data, response) = try await URLSession.shared.data(for: request)
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 502
            let itag = Self.pathValue("itag", in: url) ?? "-"
            record("\(status) \(kind) itag \(itag)")
            if retries > 0 {
                let elapsed = Int(Date.now.timeIntervalSince(firstTry))
                let sinceStart = Int(firstTry.timeIntervalSince(startDate))
                retryLog.append(
                    "itag \(itag) gosq \(Self.pathValue("gosq", in: url) ?? "-"): first 401 at \(sinceStart) s,"
                        + " \(status == 401 ? "still 401" : "\(status)") after \(retries) retries / \(elapsed) s"
                )
            }
            if status >= 400 {
                let finalHost = http?.url?.host ?? "?"
                let redirected = finalHost != url.host ? " · redirected to \(finalHost)" : ""
                let body = String(decoding: data.prefix(200), as: UTF8.self)
                failures.append(
                    "\(status) \(kind) itag \(itag) gosq \(Self.pathValue("gosq", in: url) ?? "-")"
                        + " · range \(headers["range"] ?? "none")\(redirected)"
                        + " · \(Self.pathValue("playlist_type", in: url) ?? "")"
                        + "\n   body: \(body.isEmpty ? "(empty)" : body)"
                )
            }

            var body = data
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") {
                body = Data(Self.rewritePlaylist(text, keepingURLs: servesMasterOnly).utf8)
            }
            var responseHeaders: [String: String] = [:]
            if let type = http?.value(forHTTPHeaderField: "Content-Type") {
                responseHeaders["Content-Type"] = type
            }
            if let range = http?.value(forHTTPHeaderField: "Content-Range") {
                responseHeaders["Content-Range"] = range
            }
            send(
                status: status,
                reason: HTTPURLResponse.localizedString(forStatusCode: status),
                headers: responseHeaders,
                body: body,
                on: connection
            )
        } catch {
            record("error \(kind): \(error.localizedDescription)")
            send(status: 502, reason: "Bad Gateway", headers: [:], body: Data(), on: connection)
        }
    }

    private func record(_ entry: String) {
        log.append(entry)
        let key = entry
        counts[key, default: 0] += 1
    }

    private func send(status: Int, reason: String, headers: [String: String], body: Data, on connection: NWConnection) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
