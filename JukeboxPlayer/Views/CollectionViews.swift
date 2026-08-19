import SwiftUI

/// 按「歌手 / 专辑」把曲库分组，点击进入该组的全部歌曲。
struct GroupedListView: View {
    let title: String
    let groupKey: (Track) -> String
    let placeholder: String
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore
    var searchText: String = ""

    private var groups: [(name: String, tracks: [Track])] {
        let base = store.tracks.filter {
            searchText.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
        let dict = Dictionary(grouping: base, by: groupKey)
        return dict
            .map { (name: $0.key.isEmpty ? placeholder : $0.key, tracks: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.name) { group in
                NavigationLink {
                    GroupDetailView(title: group.name, tracks: group.tracks)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: coverColors(for: group.name),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(String(group.name.prefix(1)))
                                    .foregroundStyle(.white)
                                    .font(.title3)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(group.tracks.count) 首")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listRowBackground(Color.clear)
        .overlay {
            if groups.isEmpty {
                Text("没有\(title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

/// 某个歌手 / 专辑下的全部歌曲列表。
struct GroupDetailView: View {
    let title: String
    let tracks: [Track]
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore
    @State private var trackToAdd: Track?

    var body: some View {
        List {
            Button {
                engine.load(tracks)
                engine.play(index: 0)
            } label: {
                Label("播放全部", systemImage: "play.circle.fill")
                    .font(.headline)
            }

            ForEach(tracks) { track in
                TrackRow(
                    track: track,
                    isCurrent: isCurrent(track),
                    isPlaying: engine.isPlaying,
                    onTap: { play(track) },
                    onAddToPlaylist: { trackToAdd = $0 }
                )
                .deleteDisabled(!track.isRemovable)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listRowBackground(Color.clear)
        .containerBackground(for: .navigation) {
            SkinBackground()
        }
        .navigationTitle(title)
        .sheet(item: $trackToAdd) { track in
            AddToPlaylistSheet(track: track)
        }
    }

    private func isCurrent(_ track: Track) -> Bool {
        engine.tracks[safe: engine.currentIndex]?.id == track.id
    }

    private func play(_ track: Track) {
        // 切到该歌手/专辑的局部队列并从点击处开始播放，避免全局队列索引错位导致切歌失败。
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        engine.load(tracks)
        engine.play(index: idx)
    }
}
