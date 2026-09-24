import AVFoundation
import Network

/// TEST (do not merge): a tiny HTTP server on 127.0.0.1 that records the
/// request headers AVPlayer (streaming) and the background download service
/// send, to compare them. It answers every request with 404, so nothing is
/// played or downloaded, and nothing leaves the device.
@MainActor
final class TestHeaderCapture {
    static let shared = TestHeaderCapture()

    private static let port: NWEndpoint.Port = 8089
    private var listener: NWListener?
    private var requests: [String] = []
    private var player: AVPlayer?

    /// Starts the server, lets AVPlayer and the download service each request
    /// a playlist from it, and returns what arrived after a few seconds.
    func capture(downloadSession: AVAssetDownloadURLSession) async -> String {
        requests = []
        guard startListener() else { return "Header capture: could not start the local server." }

        // Streaming: AVPlayer loads the playlist as soon as it has an item.
        let streamURL = URL(string: "http://127.0.0.1:\(Self.port)/stream/master.m3u8")!
        player = AVPlayer(url: streamURL)

        // Downloading: the background service loads the playlist.
        let downloadURL = URL(string: "http://127.0.0.1:\(Self.port)/download/master.m3u8")!
        let configuration = AVAssetDownloadConfiguration(asset: AVURLAsset(url: downloadURL), title: "Header capture")
        let task = downloadSession.makeAssetDownloadTask(downloadConfiguration: configuration)
        task.taskDescription = "headercapture"
        task.resume()

        try? await Task.sleep(for: .seconds(6))
        task.cancel()
        player = nil
        listener?.cancel()
        listener = nil

        if requests.isEmpty {
            return "Header capture: no request arrived."
        }
        return (["Header capture"] + requests).joined(separator: "\n\n")
    }

    private func startListener() -> Bool {
        guard let listener = try? NWListener(using: .tcp, on: Self.port) else { return false }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Self.receive(on: connection, buffer: Data())
        }
        listener.start(queue: .main)
        self.listener = listener
        return true
    }

    /// Reads until the end of the request headers, records them and answers 404.
    private nonisolated static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            let text = String(decoding: buffer, as: UTF8.self)
            if text.contains("\r\n\r\n") || isComplete || error != nil {
                let head = text.components(separatedBy: "\r\n\r\n").first ?? text
                Task { @MainActor in
                    TestHeaderCapture.shared.requests.append(head)
                }
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }
}
