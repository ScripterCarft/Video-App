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
    let descriptionText: String?
    let badges: [String]?
    let source: Source
    let playbackURL: URL?

    var youtubeURL: URL? {
        guard source == .youtube else { return playbackURL }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    /// A predictable 16:9 image keeps curated, searched, and previously saved
    /// YouTube videos on the exact same card geometry.
    var artworkURL: URL? {
        artworkURLs.first
    }

    var artworkURLs: [URL] {
        guard source == .youtube else { return thumbnailURL.map { [$0] } ?? [] }
        let candidates = [
            URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg"),
            thumbnailURL,
            URL(string: "https://i.ytimg.com/vi/\(id)/hq720.jpg"),
            URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
        ].compactMap { $0 }
        return candidates.reduce(into: []) { result, url in
            if !result.contains(url) { result.append(url) }
        }
    }

    var metadataLine: String {
        [viewCountText, publishedText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let values = duration.split(separator: ":").compactMap { Int($0) }
        switch values.count {
        case 3:
            let hours = values[0]
            let minutes = values[1]
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        case 2:
            return "\(values[0])m"
        default:
            return duration
        }
    }

    var normalizedDescription: String? {
        guard let descriptionText else { return nil }
        let value = descriptionText
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return value.isEmpty ? nil : value
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
            views: "Science & ideas",
            description: "What if every decision you make is the inevitable result of everything that came before? Kurzgesagt explores one of philosophy’s oldest questions through science and animation.",
            badges: ["HD", "CC"]
        ),
        .youtube(
            id: "d6iQrh2TK98",
            title: "Why Is This Number Everywhere?",
            channel: "Veritasium",
            duration: "22:08",
            published: "Editor’s pick",
            views: "Mathematics",
            description: "Veritasium follows a surprising mathematical constant through geometry, probability, and the patterns hidden in the world around us.",
            badges: ["HD", "CC"]
        ),
        .youtube(
            id: "h6fcK_fRYaI",
            title: "The Egg — A Short Story",
            channel: "Kurzgesagt – In a Nutshell",
            duration: "7:55",
            published: "Essential",
            views: "Animated story",
            description: "A short animated story about life, identity, and the connections between people, adapted by Kurzgesagt.",
            badges: ["HD", "CC"]
        ),
        .youtube(
            id: "pTn6Ewhb27k",
            title: "The Simplest Math Problem No One Can Solve",
            channel: "Veritasium",
            duration: "22:09",
            published: "Staff pick",
            views: "Mathematics",
            description: "A deceptively simple mathematical problem leads to patterns that have resisted a complete explanation for decades.",
            badges: ["HD", "CC"]
        )
    ]

    static func youtube(
        id: String,
        title: String,
        channel: String,
        duration: String? = nil,
        published: String? = nil,
        views: String? = nil,
        thumbnailURL: URL? = nil,
        description: String? = nil,
        badges: [String]? = nil
    ) -> Video {
        Video(
            id: id,
            title: title,
            channelName: channel,
            thumbnailURL: thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            duration: duration,
            publishedText: published,
            viewCountText: views,
            descriptionText: description,
            badges: badges,
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
