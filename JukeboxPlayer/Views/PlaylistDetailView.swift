import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Binding var trackToAdd: Track?

    @EnvironmentObject private var store: TrackStore
    @EnvironmentObject private var engine: PlayerEngine

    private var tracks: [Track] { store.tracks(in: playlist) }

    var body: some View {
        List {
            if !tracks.isEmpty {
                Button {
                    engine.load(tracks)
                    engine.play(index: 0)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            ForEach(tracks) { track in
                TrackRow(
                    track: track,
                    isCurrent: isCurrent(track),
                    isPlaying: engine.isPlaying,
                    onTap: { play(track) },
                    onAddToPlaylist: { trackToAdd = $0 }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.removeTrack(track.id, from: playlist.id) } label: {
                        Label("移除", systemImage: "minus.circle")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .overlay {
            if tracks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("歌单是空的").font(.headline)
                    Text("去「歌曲」页把音乐加进来").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func isCurrent(_ track: Track) -> Bool {
        engine.tracks[safe: engine.currentIndex]?.id == track.id
    }

    private func play(_ track: Track) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        engine.load(tracks)
        engine.play(index: idx)
    }
}
