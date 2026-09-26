import SwiftUI

/// The detail screen's toolbar button: Download, the progress ring while a
/// download runs (tap to stop), or the downloaded state, which opens the
/// renew-or-remove choice right at the button.
struct DownloadToolbarButton: View {
    let video: Video

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if let activity = downloads.activity(for: video) {
            Button {
                downloads.cancel(video)
            } label: {
                DownloadProgressRing(progress: activity.progress)
            }
        } else if downloads.isDownloaded(video) {
            // The system menu opens from the button itself.
            Menu {
                Section {
                    Button("Download Again to Renew", systemImage: "arrow.clockwise") {
                        downloads.renew(video)
                    }
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        downloads.remove(video)
                    }
                } header: {
                    Text("Renew to keep this download from Videos or remove it from your iPhone.")
                }
            } label: {
                Label("Downloaded", systemImage: "arrow.down.circle.fill")
            }
        } else {
            Button("Download", systemImage: "arrow.down") {
                downloads.download(video)
            }
            .disabled(!downloads.canDownload(video))
        }
    }
}

/// The Download entry of a card's context menu, beside Save and Share. A
/// downloaded video has none; its menu offers Remove Download instead.
struct DownloadMenuButton: View {
    let video: Video
    let onAction: () -> Void

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if downloads.activity(for: video) != nil {
            Button("Stop", systemImage: "stop.circle") {
                downloads.cancel(video)
                onAction()
            }
        } else if !downloads.isDownloaded(video) {
            Button("Download", systemImage: "arrow.down") {
                downloads.download(video)
                onAction()
            }
            .disabled(!downloads.canDownload(video))
        }
    }
}
