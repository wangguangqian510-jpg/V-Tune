import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        ZStack {
            // 全局背景：跟随皮肤（自定义图 → 当前播放封面 → 封面色渐变），让曲库/设置页也有氛围。
            // 用 UIScreen.main.bounds 做明确尺寸，避免 GeometryReader 干扰内容安全区。
            backgroundLayer
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea()
                .zIndex(-1)

            // 内容层：不套 GeometryReader、不加显式 frame，让它按设备安全区自然布局。
            // 这样不会把主页/导入歌词/列表整体上顶。
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
    }

    private var backgroundLayer: some View {
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
    }
}
