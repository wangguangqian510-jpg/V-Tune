import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("V-Tune")
                .navigationBarTitleDisplayMode(.inline)
        }
        // 全局皮肤层: 挂在导航栈外侧 → 覆盖曲库/设置/歌单等所有页面, 且触摸全穿透
        .overlay(SkinGlobalOverlay())
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
