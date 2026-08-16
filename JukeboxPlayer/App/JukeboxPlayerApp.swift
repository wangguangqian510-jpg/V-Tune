import SwiftUI

@main
struct JukeboxPlayerApp: App {
    @StateObject private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .onAppear {
                    // 加载示例播放列表。换成你自己的曲目即可。
                    engine.load(Track.samples)
                }
        }
    }
}
