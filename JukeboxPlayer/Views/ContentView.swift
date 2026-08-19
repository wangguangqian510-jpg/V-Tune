import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        // deployment target 已提到 iOS 18，用官方 .containerBackground(for: .navigation)
        // 做 NavigationStack 全局背景。注意：必须挂在 NavigationStack 的**根内容**上
        // （而不是 NavigationStack 外层），每个 push 出去的页面也要各自挂一份，
        // 这样每一级页面都能透出统一的背景图。
        NavigationStack {
            LibraryView()
                .navigationTitle("乐影")
                .navigationBarTitleDisplayMode(.inline)
                .containerBackground(for: .navigation) {
                    SkinBackground()
                }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// 共享皮肤背景：自定义图片优先 → 专辑封面 → 封面色渐变兜底。
/// blur 半径降到 8（25 依然太重：用户反馈背景太糊看不清，且拖动滑杆仍卡顿）。
struct SkinBackground: View {
    @EnvironmentObject var store: TrackStore
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        Group {
            if store.backgroundModeEnum == .custom, let img = store.loadCustomBackground() {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 8, opaque: false)
                    .overlay(Color.black.opacity(1 - store.customBackgroundOpacity))
            } else if let img = engine.artwork {
                Image(uiImage: img).resizable().scaledToFill()
                    .blur(radius: 8, opaque: false).overlay(Color.black.opacity(0.5))
            } else {
                let base = engine.currentCover.isEmpty ? [Color.black] : engine.currentCover
                LinearGradient(colors: base.map { $0.opacity(0.5) } + [.black],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
