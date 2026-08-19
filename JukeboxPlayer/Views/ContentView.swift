import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        // 用 ZStack(alignment: .top) 而不是 .background { ... }，把背景图放到
        // NavigationStack 下面一层显式渲染，避免被 NavigationStack 的系统背景遮住。
        // 关键：.ignoresSafeArea() 只挂在 backgroundLayer 自己，不污染 NavigationStack，
        // 所以内容仍按安全区自然布局（顶部不被推到状态栏下面）。
        ZStack(alignment: .top) {
            backgroundLayer
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea()

            NavigationStack {
                LibraryView()
                    .navigationTitle("乐影")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
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
