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
        .background {
            backgroundLayer
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .ignoresSafeArea()
        }
        // 迷你播放条已移入 LibraryView 底部（见 LibraryView）：
        // 1) 去掉 .safeAreaInset(edge:.bottom) —— 它会在点播放(hasTrack=true)时与
        //    .searchable 搜索栏冲突，导致搜索框消失、列表整体偏上、底部条被挤得点不到。
        // 2) 背景改用 .background 挂载，不再用 ZStack + ignoresSafeArea 把顶层安全区
        //    “漏”给 NavigationStack，避免内容上顶到状态栏。
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
