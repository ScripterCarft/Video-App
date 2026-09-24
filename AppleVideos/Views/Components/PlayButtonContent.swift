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
                    Gauge(value: progress.fraction) {
                        EmptyView()
                    }
                    .gaugeStyle(.linearCapacity)
                    .labelsHidden()
                    .frame(width: 44)
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
