import Foundation

/// 歌单（播放列表）。仅存曲目 ID，真正的 Track 在 TrackStore 里按 ID 解析。
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    let createdAt: Date
    var coverSeed: String

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], coverSeed: String = "") {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = Date()
        self.coverSeed = coverSeed.isEmpty ? name : coverSeed
    }
}
