import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var store: TrackStore

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 全局背景：跟随皮肤（自定义图 → 当前播放封面 → 封面色渐变），让曲库/设置页也有氛围。
                // 关键：背景必须用明确的屏幕尺寸约束，绝不能 .frame(maxWidth:.infinity)。
                // 否则 Image 会退回原始像素尺寸，把整个 ZStack 撑宽，导致主页/播放页/歌词页全被拉宽。
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
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()

                NavigationStack {
                    LibraryView()
                        .navigationTitle("乐影")
                        .navigationBarTitleDisplayMode(.large)
                }
                .frame(width: geo.size.width, height: geo.size.height)
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
}
