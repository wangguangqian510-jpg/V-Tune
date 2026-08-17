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
    /// 歌词（LRC 或纯文本）；可选以兼容旧存档
    let lyrics: String?
}

/// 歌单 JSON 导入时的可预期错误。
enum ImportError: LocalizedError {
    case invalidFormat
    case noTracks
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "JSON 格式无法识别（需要包含曲目数组，如 tracks / list / songs）"
        case .noTracks:      return "没有找到任何可导入的音频链接（每条需含 http(s):// 或 file:// 的 url 字段）"
        }
    }
}

/// JSON 导入结果：导入的曲目数与自动生成的歌单名。
struct PlaylistImportResult {
    let count: Int
    let playlistName: String
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
            isFavorite: favoriteIDs.contains(record.id),
            lyrics: record.lyrics ?? ""
        )
    }

    // MARK: - 导入

    /// 从 Files / Share Sheet 导入一个音频文件到 App Documents。
    /// 返回新建曲目的 ID（失败或跳过时返回 nil）。
    ///
    /// 为避免大文件阻塞主线程，这里先把文件复制进 Documents 并立即生成一条 record，
    /// 然后在后台异步解析 ID3 / MP4 标签；解析完成后再更新 record 并刷新 UI。
    func importFile(from url: URL) throws -> UUID? {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dest = uniqueURL(in: docs, for: url)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try fileManager.copyItem(at: url, to: dest)

        // 先用文件名兜底生成 record，保证导入立刻成功并出现在歌单里。
        let baseTitle = (dest.lastPathComponent as NSString).deletingPathExtension
        let id = addImportedRecord(filename: dest.lastPathComponent, title: baseTitle, artist: "未知歌手", album: "", lyrics: "")

        // 后台解析真实标签，完成后更新。
        Task.detached(priority: .userInitiated) { [weak self] in
            let tags = readAudioTags(from: dest)
            guard let self = self else { return }
            await MainActor.run {
                guard self.records[id] != nil else { return }
                let title = (tags.title?.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap { $0.isEmpty ? nil : $0 } ?? baseTitle
                let artist = (tags.artist?.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"
                let album = tags.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let lyrics = tags.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let updated = TrackRecord(
                    id: id,
                    title: title,
                    artist: artist,
                    album: album,
                    source: .imported,
                    urlString: dest.lastPathComponent,
                    coverSeed: dest.lastPathComponent,
                    lyrics: lyrics.isEmpty ? nil : lyrics
                )
                self.records[id] = updated
                self.saveRecords()
                self.refresh()
                self.catalogVersion += 1
            }
        }
        return id
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
            coverSeed: url.absoluteString,
            lyrics: nil
        )
        records[id] = record
        saveRecords()
        refresh()
        catalogVersion += 1
    }

    /// 导入一个「歌单 JSON」：包含多首带直链音频 URL 的曲目。
    /// 容错解析多种常见字段命名；缺 URL 的条目会被跳过。
    /// 导入后会自动创建一个歌单并把曲目放进去。返回导入数与歌单名。
    /// 抛错仅发生在「整体格式无法识别」或「一条都没导进来」时。
    func importPlaylist(from data: Data) throws -> PlaylistImportResult {
        let parsed = try JSONSerialization.jsonObject(with: data)

        let items: [[String: Any]]
        var name: String?
        if let dict = parsed as? [String: Any] {
            // 常见曲目数组键名都试一遍
            items = dict.compactMap { key, value in
                (["tracks", "list", "songs", "data", "items", "musics"].contains(key) ? value : nil)
            }
            .first(where: { $0 is [[String: Any]] }) as? [[String: Any]] ?? []
            // 常见歌单名字段
            name = firstString(dict, keys: ["name", "title", "playlist", "listName", "歌单名", "名称"])
        } else if let arr = parsed as? [[String: Any]] {
            items = arr
        } else {
            throw ImportError.invalidFormat
        }

        let ids = importItems(items)
        if ids.isEmpty {
            throw ImportError.noTracks
        }

        let playlistName = name ?? "导入歌单"
        let playlist = createPlaylist(name: playlistName)
        addTracks(ids, to: playlist.id)
        return PlaylistImportResult(count: ids.count, playlistName: playlistName)
    }

    private func importItems(_ items: [[String: Any]]) -> [UUID] {
        var ids: [UUID] = []
        for item in items {
            guard let rawURL = firstString(item, keys: ["url", "src", "play_url", "playUrl", "audio", "link", "mp3", "file"]) else { continue }
            let title = firstString(item, keys: ["title", "name", "song", "songname", "musicName", "music_name"]) ?? ""
            let artist = firstString(item, keys: ["artist", "singer", "author", "singerName", "artistName"]) ?? "未知歌手"
            let album = firstString(item, keys: ["album", "albumName", "albumname"]) ?? ""
            let lyrics = firstString(item, keys: ["lyrics", "lrc", "text"])
            let sourceHint = firstString(item, keys: ["source"])?.lowercased()

            // file:// 本地路径，或显式声明 source=imported/local：按本地文件导入。
            if rawURL.hasPrefix("file://") || sourceHint == "imported" || sourceHint == "local" {
                if let id = importLocalFileRef(from: rawURL, title: title, artist: artist, album: album, lyrics: lyrics) {
                    ids.append(id)
                }
                continue
            }

            // http(s) 远程直链：作为网络音频。
            guard let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true else { continue }
            let id = UUID()
            let record = TrackRecord(
                id: id,
                title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                artist: artist,
                album: album,
                source: .remote,
                urlString: url.absoluteString,
                coverSeed: url.absoluteString,
                lyrics: lyrics
            )
            records[id] = record
            ids.append(id)
        }
        if !ids.isEmpty {
            saveRecords()
            refresh()
            catalogVersion += 1
        }
        return ids
    }

    /// 处理 JSON 中引用的本地文件（file:// 或显式 source=imported/local）：
    /// 把文件复制进 App Documents，生成一条「本地导入」记录并立即进库。
    /// 文件不存在或复制失败时返回 nil（跳过该条，不崩溃）。
    private func importLocalFileRef(from rawURL: String, title: String, artist: String, album: String, lyrics: String?) -> UUID? {
        let fileURL: URL
        if rawURL.hasPrefix("file://") {
            fileURL = URL(string: rawURL) ?? URL(fileURLWithPath: rawURL)
        } else {
            fileURL = URL(fileURLWithPath: rawURL)
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[TrackStore] 本地文件引用不存在，已跳过: \(rawURL)"); return nil
        }
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dest = uniqueURL(in: docs, for: fileURL)
        do {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: fileURL, to: dest)
        } catch {
            print("[TrackStore] 本地文件引用复制失败: \(error)"); return nil
        }
        let baseTitle = title.isEmpty ? (dest.lastPathComponent as NSString).deletingPathExtension : title
        let id = UUID()
        let record = TrackRecord(
            id: id,
            title: baseTitle,
            artist: artist,
            album: album,
            source: .imported,
            urlString: dest.lastPathComponent,
            coverSeed: dest.lastPathComponent,
            lyrics: lyrics
        )
        records[id] = record
        return id
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

    /// 批量把曲目 ID 加入指定歌单（用于导入后自动成歌单）。
    func addTracks(_ ids: [UUID], to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        for id in ids where !playlists[i].trackIDs.contains(id) {
            playlists[i].trackIDs.append(id)
        }
        savePlaylists()
    }

    func removeTrack(_ trackID: UUID, from playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[i].trackIDs.removeAll { $0 == trackID }
        savePlaylists()
    }

    // MARK: - 私有辅助

    private func addImportedRecord(filename: String, title: String, artist: String, album: String, lyrics: String) -> UUID {
        let id = UUID()
        let record = TrackRecord(
            id: id,
            title: title,
            artist: artist,
            album: album,
            source: .imported,
            urlString: filename,
            coverSeed: filename,
            lyrics: lyrics.isEmpty ? nil : lyrics
        )
        records[id] = record
        saveRecords()
        refresh()
        catalogVersion += 1
        return id
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
        do {
            let data = try JSONEncoder().encode(list)
            UserDefaults.standard.set(data, forKey: recordsKey)
        } catch {
            print("[TrackStore] saveRecords 编码失败: \(error)")
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey),
              let list = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = list
    }

    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            print("[TrackStore] savePlaylists 编码失败: \(error)")
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let list = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        favoriteIDs = Set(list)
    }

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(Array(favoriteIDs))
            UserDefaults.standard.set(data, forKey: favoritesKey)
        } catch {
            print("[TrackStore] saveFavorites 编码失败: \(error)")
        }
    }
}
