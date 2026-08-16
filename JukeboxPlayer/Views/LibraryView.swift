import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    @State private var showingImporter = false
    @State private var showingURLAlert = false
    @State private var showingErrorAlert = false
    @State private var urlString = ""
    @State private var importError: String?

    var body: some View {
        List {
            ForEach(Array(engine.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, isCurrent: index == engine.currentIndex, isPlaying: engine.isPlaying)
                    .contentShape(Rectangle())
                    .deleteDisabled(!track.isRemovable)
                    .onTapGesture { engine.play(index: index) }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .overlay {
            if engine.tracks.isEmpty {
                ProgressView("加载中…")
            }
        }
        .toolbar {
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
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("添加网络音频", isPresented: $showingURLAlert) {
            TextField("https://example.com/music.mp3", text: $urlString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {
                urlString = ""
            }
            Button("添加") {
                store.importRemoteURL(urlString)
                urlString = ""
            }
        } message: {
            Text("输入可直链播放的音频 URL")
        }
        .alert("导入失败", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var errors: [String] = []
            for url in urls {
                do {
                    try store.importFile(from: url)
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let track = engine.tracks[index]
            guard track.isRemovable else { continue }
            store.delete(track: track)
        }
    }
}
