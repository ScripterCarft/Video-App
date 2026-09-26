import SwiftUI

/// Download progress as a ring that fills from 0 to 100 % around a stop
/// symbol, like a download in progress in the App Store and TV app. The
/// button that shows it stops the download.
struct DownloadProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            Image(systemName: "stop.fill")
                .font(.system(size: 8, weight: .bold))
        }
        .frame(width: 22, height: 22)
        .accessibilityElement()
        .accessibilityLabel("Stop Download")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
