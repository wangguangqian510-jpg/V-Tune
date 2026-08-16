import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: PlayerEngine

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Jukebox 播放器")
                .navigationBarTitleDisplayMode(.large)
        }
        .safeAreaInset(edge: .bottom) {
            if engine.hasTrack {
                NowPlayingBar()
                    .environmentObject(engine)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}
