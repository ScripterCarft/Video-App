import SwiftUI

/// The detail screen's toolbar button: Download, the progress ring while a
/// download runs (tap to stop), or the downloaded state, which opens the
/// renew-or-remove choice.
struct DownloadToolbarButton: View {
    let video: Video
    @Binding var isShowingDownloadOptions: Bool

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if let activity = downloads.activity(for: video) {
            Button {
                downloads.cancel(video)
            } label: {
                DownloadProgressRing(progress: activity.progress)
            }
        } else if downloads.isDownloaded(video) {
            Button("Downloaded", systemImage: "arrow.down.circle.fill") {
                isShowingDownloadOptions = true
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

extension View {
    /// The renew-or-remove choice for a downloaded video.
    func downloadOptionsDialog(for video: Video, isPresented: Binding<Bool>) -> some View {
        modifier(DownloadOptionsDialog(video: video, isPresented: isPresented))
    }

    /// Reports a download that could not be completed, wherever the app is.
    func downloadFailureAlert() -> some View {
        modifier(DownloadFailureAlert())
    }
}

private struct DownloadOptionsDialog: ViewModifier {
    let video: Video
    @Binding var isPresented: Bool

    @Environment(DownloadManager.self) private var downloads

    func body(content: Content) -> some View {
        content.confirmationDialog("Download", isPresented: $isPresented, titleVisibility: .hidden) {
            Button("Download Again to Renew") {
                downloads.renew(video)
            }
            Button("Remove Download", role: .destructive) {
                downloads.remove(video)
            }
        } message: {
            Text("Renew to keep this download from Videos or remove it from your iPhone.")
        }
    }
}

private struct DownloadFailureAlert: ViewModifier {
    @Environment(DownloadManager.self) private var downloads

    func body(content: Content) -> some View {
        content.alert(
            "Download Failed",
            isPresented: Binding(
                get: { downloads.failure != nil },
                set: { if !$0 { downloads.failure = nil } }
            ),
            presenting: downloads.failure
        ) { failure in
            Button("Try Again") {
                downloads.download(failure.video)
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text("“\(failure.video.title)” couldn't be downloaded. \(failure.message)")
        }
    }
}
