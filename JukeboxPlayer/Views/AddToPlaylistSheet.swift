import SwiftUI

/// 从任意歌曲的「…」菜单弹出，把该曲加入已有歌单，或新建歌单后加入。
struct AddToPlaylistSheet: View {
    let track: Track
    @EnvironmentObject private var store: TrackStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建歌单") {
                    TextField("歌单名称", text: $newName)
                    Button {
                        let name = newName.isEmpty ? "我的歌单" : newName
                        let playlist = store.createPlaylist(name: name)
                        store.addTrack(track, to: playlist.id)
                        dismiss()
                    } label: {
                        Label("创建并添加", systemImage: "plus")
                    }
                }
                Section("我的歌单") {
                    if store.playlists.isEmpty {
                        Text("还没有歌单").foregroundStyle(.secondary)
                    }
                    ForEach(store.playlists) { playlist in
                        Button {
                            store.addTrack(track, to: playlist.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                if playlist.trackIDs.contains(track.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
