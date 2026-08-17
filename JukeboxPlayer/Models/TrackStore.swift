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

/// 歌单 JSON 导入时的可预期错误。
enum ImportError: LocalizedError {
    case invalidFormat
    case noTracks
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "JSON 格式无法识别（需要包含曲目数组，如 tracks / list / songs）"
        case .noTracks:      return "没有找到任何可导入的音频链接（每条需含 http(s) 的 url 字段）"
        }
    }
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

    /// 导入一个「歌单 JSON」：包含多首带直链音频 URL 的曲目。
    /// 容错解析多种常见字段命名；缺 URL 的条目会被跳过。返回成功导入的曲目数。
    /// 抛错仅发生在「整体格式无法识别」或「一条都没导进来」时。
    func importPlaylist(from data: Data) throws -> Int {
        let parsed = try JSONSerialization.jsonObject(with: data)

        let items: [[String: Any]]
        if let dict = parsed as? [String: Any] {
            // 常见曲目数组键名都试一遍
            items = dict.compactMap { key, value in
                (["tracks", "list", "songs", "data", "items", "musics"].contains(key) ? value : nil)
            }
            .first(where: { $0 is [[String: Any]] }) as? [[String: Any]] ?? []
        } else if let arr = parsed as? [[String: Any]] {
            items = arr
        } else {
            throw ImportError.invalidFormat
        }

        let imported = importItems(items)
        if imported == 0 {
            throw ImportError.noTracks
        }
        return imported
    }

    private func importItems(_ items: [[String: Any]]) -> Int {
        var imported = 0
        for item in items {
            guard let rawURL = firstString(item, keys: ["url", "src", "play_url", "playUrl", "audio", "link", "mp3", "file"]),
                  let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true else { continue }
            let title = firstString(item, keys: ["title", "name", "song", "songname", "musicName", "music_name"])
                ?? url.deletingPathExtension().lastPathComponent
            let artist = firstString(item, keys: ["artist", "singer", "author", "singerName", "artistName"]) ?? "未知歌手"
            let album = firstString(item, keys: ["album", "albumName", "albumname"]) ?? ""

            let id = UUID()
            let record = TrackRecord(
                id: id,
                title: title,
                artist: artist,
                album: album,
                source: .remote,
                urlString: url.absoluteString,
                coverSeed: url.absoluteString
            )
            records[id] = record
            imported += 1
        }
        if imported > 0 {
            saveRecords()
            refresh()
            catalogVersion += 1
        }
        return imported
    }

    /// 在字典里按候选键名取字符串，兼容「字符串」「{name:..}」「[..]」三种形态。
    private func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let s = value as? String, !s.isEmpty { return s }
            if let nested = value as? [String: Any], let s = nested["name"] as? String, !s.isEmpty { return s }
            if let arr = value as? [String], let first = arr.first, !first.isEmpty { return first }
        }
        return nil
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

    // MARK: - 存储空间 / 缓存清理

    /// 统计 App 占用空间与曲库概况。
    func storageInfo() -> StorageInfo {
        var info = StorageInfo()
        info.totalTracks = tracks.count
        info.remoteCount = tracks.filter { $0.source == .remote }.count
        info.importedFiles = tracks.filter { $0.source == .imported }.count
        info.favoriteCount = favoriteIDs.count
        info.playlistCount = playlists.count
        info.docsBytes = Self.directorySize(fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)
        info.cacheBytes = Self.directorySize(fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first)
        info.totalBytes = info.docsBytes + info.cacheBytes
        return info
    }

    /// 删除本机导入的所有本地音频文件，释放空间；网络音频链接与收藏/歌单结构保留。
    /// 返回释放的字节数。
    @discardableResult
    func clearLocalCache() -> Int64 {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        var freed: Int64 = 0
        let importedIDs = records.values.filter { $0.source == .imported }.map { $0.id }
        for id in importedIDs {
            guard let record = records[id] else { continue }
            let url = docs.appendingPathComponent(record.urlString)
            if let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                freed += size
            }
            try? fileManager.removeItem(at: url)
            records.removeValue(forKey: id)
            favoriteIDs.remove(id)
        }
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { importedIDs.contains($0) }
        }
        saveRecords(); saveFavorites(); savePlaylists()
        refresh()
        catalogVersion += 1
        return freed
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url = url else { return 0 }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: url,
                  includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
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
