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
        // 导航栏背景也透明，让 UIWindow 层的全局背景透出来。
        .toolbarBackground(.hidden, for: .navigationBar)
        // 全局背景已移到 UIWindow 层（见 WindowBackground），
        // 不再在 NavigationStack 上挂载 backgroundLayer，避免被系统背景遮住。
    }
}
