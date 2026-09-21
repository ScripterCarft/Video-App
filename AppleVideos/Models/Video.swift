import Foundation

struct Video: Identifiable, Hashable, Codable, Sendable {
    enum Source: String, Codable, Sendable {
        case youtube
        case direct
    }

    let id: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
    let duration: String?
    let publishedText: String?
    let viewCountText: String?
    let source: Source
    let playbackURL: URL?

    var youtubeURL: URL? {
        guard source == .youtube else { return playbackURL }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    var metadataLine: String {
        [viewCountText, publishedText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension Video {
    static let curated: [Video] = [
        .youtube(
            id: "aqz-KE-bpKQ",
            title: "Big Buck Bunny — an open movie",
            channel: "Blender Foundation",
            duration: "9:56",
            published: "Featured",
            views: "A cinematic short"
        ),
        .youtube(
            id: "M7lc1UVf-VE",
            title: "YouTube Developers Live: Embedded Player",
            channel: "Google for Developers",
            duration: "1:12",
            published: "Developer showcase",
            views: "Official sample"
        ),
        .youtube(
            id: "ScMzIvxBSi4",
            title: "A quiet moment in nature",
            channel: "Apple Videos Editorial",
            duration: "0:30",
            published: "Today",
            views: "Recommended"
        ),
        .youtube(
            id: "ysz5S6PUM-U",
            title: "Sintel — open movie trailer",
            channel: "Blender Foundation",
            duration: "0:52",
            published: "Staff pick",
            views: "Animation"
        )
    ]

    static func youtube(
        id: String,
        title: String,
        channel: String,
        duration: String? = nil,
        published: String? = nil,
        views: String? = nil,
        thumbnailURL: URL? = nil
    ) -> Video {
        Video(
            id: id,
            title: title,
            channelName: channel,
            thumbnailURL: thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            duration: duration,
            publishedText: published,
            viewCountText: views,
            source: .youtube,
            playbackURL: nil
        )
    }
}

struct VideoPlaylist: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var videoIDs: [String]

    init(id: UUID = UUID(), name: String, videoIDs: [String] = []) {
        self.id = id
        self.name = name
        self.videoIDs = videoIDs
    }
}

