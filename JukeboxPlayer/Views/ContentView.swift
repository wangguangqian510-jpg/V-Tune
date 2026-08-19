import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("乐影")
                .navigationBarTitleDisplayMode(.inline)
        }
        // 导航栏背景透明，让底层 backgroundLayer 透出来。
        .toolbarBackground(.hidden, for: .navigationBar)
        // 纯 SwiftUI 背景：挂在 NavigationStack 的 .background 上，不操作 UIWindow，
        // 避免启动早期对 window 层级硬插入导致的崩溃。配合各 List 的透明化，
        // 自定义背景能统一透到主页/曲库/歌手专辑/歌单/设置页。
        .background { backgroundLayer }
    }

    private var backgroundLayer: some View {
        Group {
            if store.backgroundModeEnum == .custom, let img = store.loadCustomBackground() {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 60, opaque: false)
                    .overlay(Color.black.opacity(1 - store.customBackgroundOpacity))
            } else if let img = engine.artwork {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 60, opaque: false).overlay(Color.black.opacity(0.5))
            } else {
                let base = engine.currentCover.isEmpty ? [Color.black] : engine.currentCover
                LinearGradient(colors: base.map { $0.opacity(0.5) } + [.black],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
