import SwiftUI

@main
struct JukeboxPlayerApp: App {
    @StateObject private var engine = PlayerEngine()
    @StateObject private var store = TrackStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(store)
                .onAppear {
                    engine.load(store.tracks)
                }
                .onChange(of: store.tracks) { newTracks in
                    engine.load(newTracks)
                }
        }
    }
}
