import SwiftUI



struct TrackRow: View {

    let track: Track

    let isCurrent: Bool

    let isPlaying: Bool

    /// 点击整行时的回调（播放）。nil 表示不可点击。

    var onTap: (() -> Void)? = nil

    /// 点击「添加到歌单」时回调。nil 表示不显示该菜单。

    var onAddToPlaylist: ((Track) -> Void)? = nil



    @EnvironmentObject private var store: TrackStore



    var body: some View {

        HStack(spacing: 14) {

            HStack(spacing: 14) {

                coverSquare

                VStack(alignment: .leading, spacing: 4) {

                    Text(track.title)

                        .font(.headline)

                        .lineLimit(1)

                        .foregroundStyle(Color.primary)

                    Text(track.artist)

                        .font(.subheadline)

                        .foregroundStyle(.secondary)

                        .lineLimit(1)

                }

            }

            .contentShape(Rectangle())

            .onTapGesture { onTap?() }



            Spacer(minLength: 0)



            Button {

                withAnimation(.easeInOut(duration: 0.18)) { store.toggleFavorite(track) }

            } label: {

                Image(systemName: track.isFavorite ? "heart.fill" : "heart")

                    .foregroundStyle(track.isFavorite ? .pink : .secondary)

                    .frame(width: 28, height: 28)

            }

            .buttonStyle(.plain)



            if onAddToPlaylist != nil {

                Menu {

                    Button {

                        onAddToPlaylist?(track)

                    } label: {

                        Label("移动到歌单", systemImage: "plus.circle")

                    }

                } label: {

                    Image(systemName: "ellipsis")

                        .foregroundStyle(.secondary)

                        .frame(width: 28, height: 28)

                }

                .buttonStyle(.plain)

            }

        }

        .padding(.vertical, 4)

    }



    private var coverSquare: some View {

        RoundedRectangle(cornerRadius: 10)

            .fill(LinearGradient(colors: track.cover,

                                 startPoint: .topLeading,

                                 endPoint: .bottomTrailing))

            .frame(width: 56, height: 56)

                        .overlay {
                if let img = track.artwork {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

                        .overlay {
                if isCurrent {

                    PlayingBars(isAnimating: isPlaying)

                }

            }

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

