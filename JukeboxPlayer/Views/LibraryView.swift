import SwiftUI
import UniformTypeIdentifiers

enum LibTab: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case artists = "歌手"
    case albums = "专辑"
    case playlists = "歌单"
    case favorites = "我喜欢"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    @State private var tab: LibTab = .songs
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var showingURLAlert = false
    @State private var showingPlaylistImport = false
    @State private var showingErrorAlert = false
    @State private var showingImportSuccess = false
    @State private var importSuccessText: String?
    @State private var urlString = ""
    @State private var importError: String?
    @State private var trackToAdd: Track?
    @State private var showingSettings = false

    private var filtered: [Track] {
        let base = store.tracks
        if searchText.isEmpty { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            switch tab {
            case .songs:     songList
            case .artists:   GroupedListView(title: "歌手", groupKey: { $0.artist }, placeholder: "未知歌手", searchText: searchText)
            case .albums:    GroupedListView(title: "专辑", groupKey: { $0.album }, placeholder: "未知专辑", searchText: searchText)
            case .playlists: PlaylistListView(trackToAdd: $trackToAdd)
            case .favorites: favoritesList
            }
        }
        .navigationTitle("Jukebox 播放器")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .searchable(text: $searchText, prompt: "搜索歌曲、歌手、专辑")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .item],
            allowsMultipleSelection: true
        ) { result in handleFileImport(result) }
        .alert("添加网络音频", isPresented: $showingURLAlert) {
            TextField("https://example.com/music.mp3", text: $urlString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) { urlString = "" }
            Button("添加") { store.importRemoteURL(urlString); urlString = "" }
        } message: {
            Text("输入可直链播放的音频 URL")
        }
        .alert("导入失败", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("导入成功", isPresented: $showingImportSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importSuccessText ?? "")
        }
        .sheet(item: $trackToAdd) { track in
            AddToPlaylistSheet(track: track)
        }
        .sheet(isPresented: $showingPlaylistImport) {
            ImportPlaylistSheet().environmentObject(store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(engine)
        }
    }

    // MARK: 顶部胶囊 Tab 条

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(LibTab.allCases) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                    } label: {
                        VStack(spacing: 4) {
            Text("\(t.rawValue)\(countText(for: t))")
                .font(.system(size: 15, weight: tab == t ? .semibold : .regular))
                .foregroundStyle(tab == t ? Color.primary : .secondary)
                            Capsule()
                                .fill(tab == t ? Color.accentColor : Color.clear)
                                .frame(width: 20, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    // MARK: 歌曲列表

    private var songList: some View {
        List {
            ForEach(filtered) { track in
                TrackRow(
                    track: track,
                    isCurrent: isCurrent(track),
                    isPlaying: engine.isPlaying,
                    onTap: { play(track, from: filtered) },
                    onAddToPlaylist: { trackToAdd = $0 }
                )
                .deleteDisabled(!track.isRemovable)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .overlay { if filtered.isEmpty { emptyHint("没有匹配的歌曲") } }
    }

    // MARK: 我喜欢的列表

    private var favoritesList: some View {
        List {
            ForEach(store.favoriteTracks) { track in
                TrackRow(
                    track: track,
                    isCurrent: isCurrent(track),
                    isPlaying: engine.isPlaying,
                    onTap: { play(track, from: store.favoriteTracks) },
                    onAddToPlaylist: { trackToAdd = $0 }
                )
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.favoriteTracks.isEmpty {
                emptyHint("还没有收藏\n在歌曲右侧点 ♡ 即可收藏")
            }
        }
    }

    // MARK: 工具

    private func countText(for t: LibTab) -> String {
        switch t {
        case .songs:     return " \(store.tracks.count)"
        case .playlists: return " \(store.playlists.count)"
        default:         return ""
        }
    }

    private func isCurrent(_ track: Track) -> Bool {
        engine.tracks[safe: engine.currentIndex]?.id == track.id
    }

    private func play(_ track: Track, from list: [Track]) {
        // 复用已加载的全局队列（catalogVersion 变化时已含全部曲目，包括导入的），
        // 直接按全局索引播放，避免每次点击都重建 Jukebox 导致状态丢失/远程曲播不了。
        guard let idx = store.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        engine.play(index: idx)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let track = filtered[index]
            guard track.isRemovable else { continue }
            store.delete(track: track)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }

    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showingImporter = true
                } label: {
                    Label("从 Files 导入", systemImage: "folder")
                }
                Button {
                    showingURLAlert = true
                } label: {
                    Label("粘贴音频链接", systemImage: "link")
                }
                Button {
                    showingPlaylistImport = true
                } label: {
                    Label("导入歌单 JSON", systemImage: "square.and.arrow.down.on.square")
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var errors: [String] = []
            var importedIDs: [UUID] = []
            for url in urls {
                do {
                    if let id = try store.importFile(from: url) {
                        importedIDs.append(id)
                    }
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            // 本地导入也自动归入一个歌单，避免「歌曲」进了库却不在「歌单」里。
            if !importedIDs.isEmpty {
                let fmt = DateFormatter()
                fmt.dateFormat = "MM-dd HH:mm"
                let name = importedIDs.count > 1 ? "本地导入 \(importedIDs.count) 首" : "本地导入 \(fmt.string(from: Date()))"
                let playlist = store.createPlaylist(name: name)
                store.addTracks(importedIDs, to: playlist.id)
                importSuccessText = "已导入 \(importedIDs.count) 首，已归入歌单「\(name)」"
                showingImportSuccess = true
            }
            if !errors.isEmpty {
                importError = errors.joined(separator: "\n")
                showingErrorAlert = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showingErrorAlert = true
        }
    }
}
