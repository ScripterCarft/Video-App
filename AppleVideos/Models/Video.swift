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

    /// A predictable 16:9 image keeps curated, searched, and previously saved
    /// YouTube videos on the exact same card geometry.
    var artworkURL: URL? {
        guard source == .youtube else { return thumbnailURL }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
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
            id: "UebSfjmQNvs",
            title: "Do You Have a Free Will?",
            channel: "Kurzgesagt – In a Nutshell",
            duration: "12:44",
            published: "Featured",
            views: "Science & ideas"
        ),
        .youtube(
            id: "d6iQrh2TK98",
            title: "Why Is This Number Everywhere?",
            channel: "Veritasium",
            duration: "22:08",
            published: "Editor’s pick",
            views: "Mathematics"
        ),
        .youtube(
            id: "h6fcK_fRYaI",
            title: "The Egg — A Short Story",
            channel: "Kurzgesagt – In a Nutshell",
            duration: "7:55",
            published: "Essential",
            views: "Animated story"
        ),
        .youtube(
            id: "pTn6Ewhb27k",
            title: "The Simplest Math Problem No One Can Solve",
            channel: "Veritasium",
            duration: "22:09",
            published: "Staff pick",
            views: "Mathematics"
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
