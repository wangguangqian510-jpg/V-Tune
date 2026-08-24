import SwiftUI
import UniformTypeIdentifiers

enum LibTab: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case recent = "最近"
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
    @State private var showingDocumentPicker = false
    @State private var showingURLAlert = false
    @State private var showingPlaylistImport = false
    @State private var showingErrorAlert = false
    @State private var urlString = ""
    @State private var importError: String?
    @State private var trackToAdd: Track?

    private var filtered: [Track] {
        let base = store.libraryTracks
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
            case .recent:    recentList
            case .artists:   GroupedListView(title: "歌手", groupKey: { $0.artist }, placeholder: "未知歌手", searchText: searchText)
            case .albums:    GroupedListView(title: "专辑", groupKey: { $0.album }, placeholder: "未知专辑", searchText: searchText)
            case .playlists: PlaylistListView(trackToAdd: $trackToAdd)
            case .favorites: favoritesList
            }
        }
        .navigationTitle("V-Tune")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarItems }
        .searchable(text: $searchText, prompt: "搜索歌曲、歌手、专辑")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, UTType(filenameExtension: "flac")!, .mp3, .mpeg4Audio, .wav, .mpeg4Movie, .movie, .video],
            allowsMultipleSelection: true
        ) { result in handleFileImport(result) }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(isPresented: $showingDocumentPicker)
                .environmentObject(store)
        }
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
        .alert("导入结果", isPresented: Binding(
            get: { store.importNotice != nil },
            set: { if !$0 { store.dismissImportNotice() } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(store.importNotice ?? "")
        }
        .sheet(item: $trackToAdd) { track in
            AddToPlaylistSheet(track: track)
        }
        .sheet(isPresented: $showingPlaylistImport) {
            ImportPlaylistSheet().environmentObject(store)
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
                            Text(t.rawValue)
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
        .overlay { if filtered.isEmpty { emptyHint(searchText.isEmpty ? "没有未归档的歌曲\n已加入歌单的曲目请在「歌单」页查看" : "没有匹配的歌曲") } }
    }

    // MARK: 最近播放列表（数据源 store.recentTracks 一直在记录,补 UI 入口）

    private var recentList: some View {
        List {
            ForEach(store.recentTracks) { track in
                TrackRow(
                    track: track,
                    isCurrent: isCurrent(track),
                    isPlaying: engine.isPlaying,
                    onTap: { play(track, from: store.recentTracks) },
                    onAddToPlaylist: { trackToAdd = $0 }
                )
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.recentTracks.isEmpty {
                emptyHint("还没有播放记录\n去歌曲页点一首试试")
            }
        }
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

    private func isCurrent(_ track: Track) -> Bool {
        engine.tracks[safe: engine.currentIndex]?.id == track.id
    }

    private func play(_ track: Track, from list: [Track]) {
        // 修复：必须切到当前列表再取索引播放，否则从歌单/歌手页播放后 engine.tracks
        // 被局部列表污染（engine.load 用歌单子集替换了全库），回主库/我喜欢页点歌时
        // 用全库 index 越界 -> 点歌无反应；且搜索/收藏队列顺序也会错（next 跳错歌）。
        guard let idx = list.firstIndex(where: { $0.id == track.id }) else { return }
        engine.load(list)
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
        Group {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink {
                SettingsView()
                    .environmentObject(store)
                    .environmentObject(engine)
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showingDocumentPicker = true
                    store.noteImport("(UI)", ok: true, message: "用户点击 UIDocumentPicker 入口（支持多选批量导入）")
                } label: {
                    Label("从 Files 导入（批量）", systemImage: "folder.badge.plus")
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
            } label: {
                Image(systemName: "plus")
            }
        }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                var errors: [String] = []
                for url in urls {
                    do {
                        try await store.importFile(from: url)
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !errors.isEmpty {
                    await MainActor.run {
                        importError = errors.joined(separator: "\n")
                        showingErrorAlert = true
                    }
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
            store.noteImport("(文件选择器)", ok: false, message: error.localizedDescription)
            showingErrorAlert = true
        }
    }
}

// MARK: - UIDocumentPicker 包装（asCopy: true 让系统拷贝到可读临时目录，绕过重签名/沙盒权限问题）

struct DocumentPicker: UIViewControllerRepresentable {
    @EnvironmentObject var store: TrackStore
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        store.noteImport("(UI)", ok: true, message: "UIDocumentPicker 正在呈现")
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio, UTType(filenameExtension: "flac")!, .mp3, .mpeg4Audio, .wav, .mpeg4Movie, .movie, .video], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.store.noteImport("(UI)", ok: true, message: "UIDocumentPicker 选中 \(urls.count) 个文件")
            Task { @MainActor in
                var errors: [String] = []
                for url in urls {
                    do {
                        try await parent.store.importFile(from: url)
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !errors.isEmpty {
                    parent.store.reportImportResult(errors.joined(separator: "\n"))
                }
                parent.isPresented = false
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.store.noteImport("(UI)", ok: false, message: "UIDocumentPicker 用户取消")
            parent.isPresented = false
        }
    }
}
