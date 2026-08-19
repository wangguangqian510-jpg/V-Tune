import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        ZStack {
            // 全局背景：跟随皮肤（自定义图 → 当前播放封面 → 封面色渐变），让曲库/设置页也有氛围。
            Group {
                if store.backgroundModeEnum == .custom, let img = store.loadCustomBackground() {
                    Image(uiImage: img).resizable().scaledToFill()
                        .blur(radius: 60, opaque: false).overlay(Color.black.opacity(0.5))
                } else if let img = engine.artwork {
                    Image(uiImage: img).resizable().scaledToFill()
                        .blur(radius: 60, opaque: false).overlay(Color.black.opacity(0.5))
                } else {
                    LinearGradient(colors: engine.currentCover.map { $0.opacity(0.5) } + [.black],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            NavigationStack {
                LibraryView()
                    .navigationTitle("乐影")
                    .navigationBarTitleDisplayMode(.large)
            }
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
