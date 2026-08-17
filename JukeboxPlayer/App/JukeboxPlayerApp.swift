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
                engine.attach(store)
                engine.load(store.tracks)
            }
        .onChange(of: store.catalogVersion) { _ in
            engine.load(store.tracks)
        }
        }
    }
}
