import SwiftUI

/// 列表底部的迷你播放条，点击展开全屏播放页。
struct NowPlayingBar: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: engine.currentCover,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.title).font(.subheadline.bold()).lineLimit(1)
                if let error = engine.lastError {
                    Text("⚠️ \(error)")
                        .font(.caption).foregroundStyle(.red).lineLimit(3)
                } else {
                    Text(engine.artist.isEmpty ? "未知艺术家" : engine.artist)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button { engine.previous() } label: {
                Image(systemName: "backward.fill").font(.title3)
            }
            .buttonStyle(.plain)

            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 28)
            }
            .buttonStyle(.plain)

            Button { engine.next() } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .fullScreenCover(isPresented: $expanded) {
            NowPlayingView()
                .environmentObject(engine)
                .environmentObject(store)
        }
    }
}
