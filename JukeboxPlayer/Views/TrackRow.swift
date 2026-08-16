import SwiftUI

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: track.cover,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .overlay {
                    if isCurrent {
                        PlayingBars(isAnimating: isPlaying)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// 播放中显示的律动小竖条。
struct PlayingBars: View {
    let isAnimating: Bool
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: animate ? 16 : 6)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.12)
                            : .default,
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
        .onChange(of: isAnimating) { newValue in animate = newValue }
    }
}
