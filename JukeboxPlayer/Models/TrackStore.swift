import Foundation
import SwiftUI

/// 持久化记录：存标题、路径、来源等，不存 Color（Color 不便于编码）。
struct TrackRecord: Codable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let source: TrackSource
    /// 本地文件：仅存文件名；远程音频：存完整 URL 字符串
    let urlString: String
    let coverSeed: String
}

/// 管理示例曲 + 用户导入的本地/远程音频 + 歌单 + 收藏。
/// 本地音频复制到 App Documents 目录，元数据用 JSON 存 UserDefaults。
@MainActor
final class TrackStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    /// 仅在「曲库结构」变化（导入/删除）时自增，用于触发播放引擎重载；
    /// 收藏态变化不计入，避免一点收藏就打断播放。
    @Published private(set) var catalogVersion: Int = 0

    private let fileManager = FileManager.default
    private let recordsKey = "JukeboxTrackRecords_v1"
    private let playlistsKey = "JukeboxPlaylists_v1"
    private let favoritesKey = "JukeboxFavoriteIDs_v1"
    private var records: [UUID: TrackRecord] = [:]
    private var favoriteIDs: Set<UUID> = []

    init() {
        loadRecords()
        loadPlaylists()
        loadFavorites()
        refresh()
    }

    // MARK: - 派生数据

    var favoriteTracks: [Track] { tracks.filter { $0.isFavorite } }

    func tracks(in playlist: Playlist) -> [Track] {
        let set = Set(playlist.trackIDs)
        return tracks.filter { set.contains($0.id) }
    }

    // MARK: - 重建曲库

    /// 重新扫描本地文件 + 重建播放列表。收藏状态从 favoriteIDs 回填。
    func refresh() {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            tracks = Track.samples
            return
        }

        var userTracks: [Track] = []
        for record in records.values {
            switch record.source {
            case .imported:
                let url = docs.appendingPathComponent(record.urlString)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                userTracks.append(makeTrack(record: record, url: url, source: .imported))
            case .remote:
                guard let url = URL(string: record.urlString) else { continue }
                userTracks.append(makeTrack(record: record, url: url, source: .remote))
            case .sample:
                break
            }
        }

        userTracks.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        tracks = Track.samples + userTracks
    }

    private func makeTrack(record: TrackRecord, url: URL, source: TrackSource) -> Track {
        Track(
            id: record.id,
            title: record.title,
            artist: record.artist,
            album: record.album,
            url: url,
            cover: coverColors(for: record.coverSeed),
            source: source,
            isFavorite: favoriteIDs.contains(record.id)
        )
    }

    // MARK: - 导入

    /// 从 Files / Share Sheet 导入一个音频文件到 App Documents。
    func importFile(from url: URL) throws {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dest = uniqueURL(in: docs, for: url)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try fileManager.copyItem(at: url, to: dest)

        // 读真实 ID3 / MP4 标签，拿歌手、专辑、标题；读不到则用文件名兜底。
        let tags = readAudioTags(from: dest)
        let baseTitle = (dest.lastPathComponent as NSString).deletingPathExtension
        let title = (tags.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? baseTitle
        let artist = (tags.artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"
        let album = tags.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        addImportedRecord(filename: dest.lastPathComponent, title: title, artist: artist, album: album)
    }

    /// 添加一个远程音频 URL。
    func importRemoteURL(_ urlString: String) {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return }
        let id = UUID()
        let record = TrackRecord(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            artist: "网络音频",
            album: "",
            source: .remote,
            urlString: url.absoluteString,
            coverSeed: url.absoluteString
        )
        records[id] = record
        saveRecords()
        refresh()
        catalogVersion += 1
    }

    /// 删除一条本地或远程曲目（同时清理收藏与歌单引用）
    func delete(track: Track) {
        guard track.isRemovable else { return }
        if track.isLocalFile {
            try? fileManager.removeItem(at: track.url)
        }
        records.removeValue(forKey: track.id)
        favoriteIDs.remove(track.id)
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { $0 == track.id }
        }
        saveFavorites()
        savePlaylists()
        saveRecords()
        refresh()
        catalogVersion += 1
    }

    // MARK: - 收藏（我喜欢）

    func toggleFavorite(_ track: Track) {
        if favoriteIDs.contains(track.id) {
            favoriteIDs.remove(track.id)
        } else {
            favoriteIDs.insert(track.id)
        }
        saveFavorites()
        refresh()
    }

    // MARK: - 歌单（播放列表）

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        savePlaylists()
        return playlist
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func renamePlaylist(_ id: UUID, name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = name
        savePlaylists()
    }

    func addTrack(_ track: Track, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[i].trackIDs.contains(track.id) {
            playlists[i].trackIDs.append(track.id)
            savePlaylists()
        }
    }

    func removeTrack(_ trackID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        savePlaylists()
    }

    // MARK: - 私有辅助

    private func addImportedRecord(filename: String, title: String, artist: String, album: String) {
        let id = UUID()
        let record = TrackRecord(
            id: id,
            title: title,
            artist: artist,
            album: album,
            source: .imported,
            urlString: filename,
            coverSeed: filename
        )
        records[id] = record
        saveRecords()
        refresh()
        catalogVersion += 1
    }

    private func uniqueURL(in directory: URL, for source: URL) -> URL {
        var dest = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: dest.path) else { return dest }

        let base = (source.lastPathComponent as NSString).deletingPathExtension
        let ext = source.pathExtension
        var counter = 1
        repeat {
            dest = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        } while fileManager.fileExists(atPath: dest.path)
        return dest
    }

    // MARK: - 持久化

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let list = try? JSONDecoder().decode([TrackRecord].self, from: data) else { return }
        records = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    private func saveRecords() {
        let list = Array(records.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey),
              let list = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = list
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: playlistsKey)
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        favoriteIDs = Set(list)
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favoriteIDs)) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
