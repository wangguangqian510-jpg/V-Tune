import SwiftUI

struct PlaylistListView: View {
    @EnvironmentObject private var store: TrackStore
    @EnvironmentObject private var engine: PlayerEngine
    @Binding var trackToAdd: Track?

    @State private var showingNewAlert = false
    @State private var newName = ""

    var body: some View {
        List {
            // 行内「新建歌单」入口：避免与曲库页右上角导入 + 相邻导致误触
            Button {
                showingNewAlert = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                    Text("新建歌单").font(.headline)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            ForEach(store.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist, trackToAdd: $trackToAdd)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: coverColors(for: playlist.coverSeed),
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name).font(.headline)
                            Text("\(playlist.trackIDs.count) 首").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.deletePlaylist(playlist.id) } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .listRowBackground(Color.clear)
        // 双保险：List 视图后面挂 SkinBackground，让 plain List 也透出背景图。
        .background { SkinBackground() }
        .overlay {
            if store.playlists.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("还没有歌单").font(.headline)
                    Text("点上方「新建歌单」按钮").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .alert("新建歌单", isPresented: $showingNewAlert) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                store.createPlaylist(name: newName.isEmpty ? "我的歌单" : newName)
                newName = ""
            }
        }
    }
}
