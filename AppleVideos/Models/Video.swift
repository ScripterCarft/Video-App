import Foundation

enum ArtworkQuality: Sendable {
    case compact
    case search
    case hero

    /// The widest the artwork is drawn, in points. Images are downsampled to
    /// this width times the display scale.
    var displayWidth: CGFloat {
        switch self {
        case .compact: 272
        case .search, .hero: 440
        }
    }
}

/// One artwork URL to try. Large variants are optional downloads: they are
/// skipped in Low Data Mode and requested without constrained-network access.
struct ArtworkCandidate: Hashable, Sendable {
    let url: URL
    let isLarge: Bool
}

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
    /// A label from the source, such as YouTube's "3 days ago", or an editorial
    /// label for curated videos. Used when `publishedAt` is unknown.
    let publishedText: String?
    /// When the video was published. Stored as a date so the relative label
    /// is formatted at display time and never goes stale. Optional so that
    /// libraries saved before this field existed still decode.
    let publishedAt: Date?
    let viewCountText: String?
    let descriptionText: String?
    let badges: [String]?
    let source: Source
    let playbackURL: URL?

    var youtubeURL: URL? {
        guard source == .youtube else { return playbackURL }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    /// Artwork URLs to try in order, sharpest useful first.
    ///
    /// YouTube's 16:9 sizes are 320×180 (`mqdefault`), up to 720 wide (the
    /// search result's own thumbnail) and 1280×720 (`hq720`, `maxresdefault`,
    /// not available for every video). Cards and search rows are drawn up to
    /// ~1300 pixels wide, so the small 320 version looks soft; it is only the
    /// last resort. In Low Data Mode the 1280 variants are left out.
    func artworkCandidates(for quality: ArtworkQuality, lowData: Bool) -> [ArtworkCandidate] {
        guard source == .youtube else {
            return [thumbnailURL].compactMap { $0 }.map { ArtworkCandidate(url: $0, isLarge: false) }
        }

        func image(_ name: String) -> URL? {
            URL(string: "https://i.ytimg.com/vi/\(id)/\(name).jpg")
        }
        let small = image("mqdefault").map { ArtworkCandidate(url: $0, isLarge: false) }
        let listed = thumbnailURL.map { ArtworkCandidate(url: $0, isLarge: false) }
        let hq720 = image("hq720").map { ArtworkCandidate(url: $0, isLarge: true) }
        let maximum = image("maxresdefault").map { ArtworkCandidate(url: $0, isLarge: true) }

        let candidates: [ArtworkCandidate?]
        switch quality {
        case .compact, .search:
            candidates = [listed, hq720, small]
        case .hero:
            candidates = [maximum, hq720, listed, small]
        }

        var seen = Set<URL>()
        return candidates
            .compactMap { $0 }
            .filter { !(lowData && $0.isLarge) }
            .filter { seen.insert($0.url).inserted }
    }

    /// "3 days ago" computed now from `publishedAt`, else the stored label.
    var publishedLabel: String? {
        if let publishedAt {
            return publishedAt.formatted(.relative(presentation: .named))
        }
        return publishedText
    }

    var metadataLine: String {
        [viewCountText, publishedLabel]
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
            let minutes = values[0]
            let seconds = values[1]
            // Videos under a minute would otherwise read "0m".
            return minutes == 0 ? "\(seconds)s" : "\(minutes)m"
        default:
            return duration
        }
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
        publishedAt: Date? = nil,
        views: String? = nil,
        thumbnailURL: URL? = nil,
        description: String? = nil,
        badges: [String]? = nil
    ) -> Video {
        Video(
            id: id,
            title: title,
            channelName: channel,
            thumbnailURL: thumbnailURL,
            duration: duration,
            publishedText: published,
            publishedAt: publishedAt,
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
