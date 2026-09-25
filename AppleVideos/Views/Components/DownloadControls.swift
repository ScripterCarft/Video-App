import SwiftUI

/// The detail screen's toolbar button: Download, the progress ring while a
/// download runs (tap to stop), or the downloaded state, which opens the
/// renew-or-remove choice right at the button.
struct DownloadToolbarButton: View {
    let video: Video

    @Environment(DownloadManager.self) private var downloads
    @State private var isShowingDownloadOptions = false

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
            .popover(isPresented: $isShowingDownloadOptions) {
                DownloadOptionsPopover(video: video, isPresented: $isShowingDownloadOptions)
                    .environment(downloads)
                    // A popover at the button on iPhone too, not a sheet.
                    .presentationCompactAdaptation(.popover)
                    // A plain gray background instead of Liquid Glass, at the
                    // user's request.
                    .presentationBackground(Color(uiColor: .secondarySystemBackground))
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

/// The renew-or-remove choice for a downloaded video: the message on top,
/// then two full-width buttons separated by lines, like an action sheet.
private struct DownloadOptionsPopover: View {
    let video: Video
    @Binding var isPresented: Bool

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(spacing: 0) {
            Text("Renew to keep this download from Videos or remove it from your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Divider()

            Button {
                isPresented = false
                downloads.renew(video)
            } label: {
                Text("Download Again to Renew")
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
            }

            Divider()

            Button(role: .destructive) {
                isPresented = false
                downloads.remove(video)
            } label: {
                Text("Remove Download")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .font(.body)
        .frame(width: 290)
    }
}

extension View {
    /// Reports a download that could not be completed, wherever the app is.
    func downloadFailureAlert() -> some View {
        modifier(DownloadFailureAlert())
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
