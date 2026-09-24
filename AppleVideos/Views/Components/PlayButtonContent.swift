import SwiftUI

/// The content of a white Play button. While the source resolves it shows a
/// spinner and Cancel; for a started video, the play symbol followed by a
/// progress bar and the remaining time, like the TV app; otherwise "Play".
struct PlayButtonContent: View {
    let progress: PlaybackProgress?
    let isPreparing: Bool

    var body: some View {
        Group {
            if isPreparing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Cancel")
                }
            } else if let progress {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(CapsuleProgressStyle())
                        .frame(width: 52)
                    Text(progress.remainingLabel)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Resume")
                .accessibilityValue("\(progress.remainingLabel) remaining")
            } else {
                Label("Play", systemImage: "play.fill")
            }
        }
        .tint(.black)
    }
}

/// A short capsule track with a filled portion, sized to sit inside a button
/// next to text, like the resume bar in the TV app.
private struct CapsuleProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        Capsule()
            .fill(.tint.opacity(0.22))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
    }
}
