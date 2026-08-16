import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var engine: PlayerEngine

    var body: some View {
        List {
            ForEach(Array(engine.tracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, isCurrent: index == engine.currentIndex, isPlaying: engine.isPlaying)
                    .contentShape(Rectangle())
                    .onTapGesture { engine.play(index: index) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if engine.tracks.isEmpty {
                ProgressView("加载中…")
            }
        }
    }
}
