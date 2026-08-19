import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        // deployment target 已提到 iOS 18，用官方 .containerBackground(for: .navigation)
        // 做 NavigationStack 全局背景：由系统绘制在每一级 push 页面后面，视觉统一、
        // 不被 List/NavigationStack 系统背景遮挡，也不需要每页自挂。
        NavigationStack {
            LibraryView()
                .navigationTitle("乐影")
                .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .containerBackground(for: .navigation) {
            SkinBackground()
        }
    }
}

/// 共享皮肤背景：自定义图片优先 → 专辑封面 → 封面色渐变兜底。
/// blur 半径降到 25（之前 60 太重，拖动背景浓度滑杆时主线程压力大会卡顿）。
struct SkinBackground: View {
    @EnvironmentObject var store: TrackStore
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        Group {
            if store.backgroundModeEnum == .custom, let img = store.loadCustomBackground() {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 25, opaque: false)
                    .overlay(Color.black.opacity(1 - store.customBackgroundOpacity))
            } else if let img = engine.artwork {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 25, opaque: false).overlay(Color.black.opacity(0.5))
            } else {
                let base = engine.currentCover.isEmpty ? [Color.black] : engine.currentCover
                LinearGradient(colors: base.map { $0.opacity(0.5) } + [.black],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
