import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Jukebox 播放器")
                .navigationBarTitleDisplayMode(.large)
        }
        .safeAreaInset(edge: .bottom) {
            if engine.hasTrack {
                NowPlayingBar()
                    .environmentObject(engine)
                    .environmentObject(store)
                    .transition(.move(edge: .bottom))
            }
        }
        // 注意：URL 处理统一在 JukeboxPlayerApp.swift 的 .onOpenURL 中完成，
        // 这里不再重复处理，避免 .lrc 等文件被二次当成音频导入。
    }
}
