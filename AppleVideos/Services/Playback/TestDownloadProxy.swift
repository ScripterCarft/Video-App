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
    func proxiedURL(for url: URL) -> URL? {
        if listener == nil {
            log = []
            counts = [:]
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
        return (["Proxy log (first requests):"] + log.prefix(12) + ["Totals:"] + totals)
            .joined(separator: "\n")
    }

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

    nonisolated private static func kind(of url: URL) -> String {
        let path = url.path
        for kind in ["hls_variant", "hls_playlist", "hls_timedtext_playlist", "timedtext", "videoplayback"]
        where path.contains(kind) {
            return kind
        }
        return url.host ?? "other"
    }

    /// Points every absolute URL in a playlist at the proxy.
    nonisolated private static func rewritePlaylist(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
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
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 502
            record("\(status) \(kind)\(headers["range"].map { _ in " range" } ?? "")")

            var body = data
            if let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") {
                body = Data(Self.rewritePlaylist(text).utf8)
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
        let key = entry.split(separator: " ").prefix(2).joined(separator: " ")
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
