import Foundation

import SwiftUI

import Combine

/// 持久化记录：存标题、路径、来源等，不存 Color（Color 不便于编码）。

struct TrackRecord: Codable {

    let id: UUID

    let title: String

    let artist: String

    let album: String

    let source: TrackSource

    /// 本地文件：仅存文件名；远程音频：存完整 URL 字符串；引用原文件：存原文件名（仅展示用）

    let urlString: String

    let coverSeed: String

    /// 内嵌 / 侧载歌词（纯文本或 LRC），无则为 nil

    let lyrics: String?

    /// 引用原文件模式：存安全书签；复制/远程模式为 nil

    let bookmark: Data?

    /// 导入去重指纹（源文件名|文件大小），仅 imported 用；相同指纹视为同一文件，不再新增记录

    let fingerprint: String?
    /// 内嵌/导入时提取的封面图（专辑图）数据，无则为 nil
    let artwork: Data?
    init(id: UUID, title: String, artist: String, album: String, source: TrackSource, urlString: String, coverSeed: String, lyrics: String?, bookmark: Data?, fingerprint: String?, artwork: Data? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.urlString = urlString
        self.coverSeed = coverSeed
        self.lyrics = lyrics
        self.bookmark = bookmark
        self.fingerprint = fingerprint
        self.artwork = artwork
    }
}

/// 歌单 JSON 导入时的可预期错误。

enum ImportError: LocalizedError {

    case invalidFormat

    case noTracks

    case noDocumentDir

    case copyFailed(String)

    var errorDescription: String? {

        switch self {

        case .invalidFormat: return "JSON 格式无法识别（需要包含曲目数组，如 tracks / list / songs）"

        case .noTracks:      return "没有找到任何可导入的音频链接（每条需含 http(s) 的 url 字段）"

        case .noDocumentDir: return "无法访问 App 文档目录，导入失败"

        case .copyFailed(let msg): return "复制文件失败：\(msg)"

        }

    }

}

/// 导入尝试的持久化日志记录（成功/失败 + 原文），供「设置 -> 导入记录」展示，

/// 用于在无 Xcode 环境下定位「导入失败但无提示」的静默问题。

struct ImportLogEntry: Codable, Identifiable {

    var id = UUID()

    let time: Date

    let fileName: String

    let ok: Bool

    let message: String

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

    /// 导入结果提示（成功/失败），供 UI 弹窗。Release 构建下 #if DEBUG 的 print 会被裁掉，

    /// 必须走 UI 提示，否则「分享导入失败」会静默吞掉，表现成「进 App 主页无事发生」。

    @Published private(set) var importNotice: String?

    /// 导入成功/失败时由导入逻辑写入提示。

    func reportImportResult(_ message: String) { importNotice = message }

    /// UI 弹窗关闭时清除提示。

    func dismissImportNotice() { importNotice = nil }

    /// 记录一次导入尝试（成功/失败），持久化供「导入记录」页查看。

    func noteImport(_ fileName: String, ok: Bool, message: String) {

        guard importDiagnosticsEnabled else { return }

        let entry = ImportLogEntry(time: Date(), fileName: fileName, ok: ok, message: message)

        importLog.insert(entry, at: 0)

        if importLog.count > 50 { importLog.removeLast() }

        saveImportLog()

    }

    private let fileManager = FileManager.default

    private let recordsKey = "JukeboxTrackRecords_v1"

    private let playlistsKey = "JukeboxPlaylists_v1"

    private let favoritesKey = "JukeboxFavoriteIDs_v1"

    private let hiddenSamplesKey = "JukeboxHiddenSampleIDs_v1"

    private let importByCopyKey = "JukeboxImportByCopy_v1"

    private var records: [UUID: TrackRecord] = [:]

    private var favoriteIDs: Set<UUID> = []

    /// 被用户「删除/隐藏」的示例曲 id（示例曲不可真删文件，只能隐藏），跨启动持久化。

    private var hiddenSampleIDs: Set<UUID> = []

    /// 导入模式：false=引用原文件（不复制，省空间，但重签名/旁载环境可能解析失败）；

    /// true=复制到 App 沙盒（最稳，默认）。默认复制，保证导入开箱即用；引用模式在设置里可手动开启。

    /// 导入模式：强制复制到 App 沙盒（最稳，重签名/旁载环境可靠）。
    /// 引用原文件（不复制）模式已废弃：重签名侧载 App 中书签解析经常失败，导致导入空白/进度无、刷新时记录消失像被全删。
    var importByCopy: Bool = true

    /// 当前已 startAccessing 的引用原文件 URL（保持作用域，供 AVPlayer 播放），refresh 时整体刷新。

    private var accessedReferencedURLs: Set<URL> = []

    /// 导入尝试日志（最新在前），持久化到 UserDefaults，供「设置 -> 导入记录」展示。

    @Published private(set) var importLog: [ImportLogEntry] = []

    private let importLogKey = "JukeboxImportLog_v1"

    /// 导入诊断日志开关：默认关闭，避免日常导入留下痕迹；开启后才会记录并展示「导入记录」。
    @Published var importDiagnosticsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(importDiagnosticsEnabled, forKey: importDiagnosticsEnabledKey) }
    }

    private let importDiagnosticsEnabledKey = "JukeboxImportDiagnosticsEnabled_v1"

    /// 最近播放记录（曲目 id，倒序，最多 50），用于「最近播放」页。

    @Published private(set) var recentIDs: [UUID] = []

    private let recentKey = "JukeboxRecentIDs_v1"

    private var cancellables = Set<AnyCancellable>()

    init() {

        // UserDefaults.bool 对未设置的 key 返回 false，故用 object(forKey:) 区分「从未设置」与「显式关掉」，

        // 默认 true（复制到 App 沙盒，开箱即用最稳）；仅当用户在设置里显式开启「引用原文件」才为 false。

        let byCopy = (UserDefaults.standard.object(forKey: importByCopyKey) as? Bool) ?? true

        importByCopy = byCopy

        loadRecords()

        loadPlaylists()

        loadFavorites()

        loadHiddenSamples()

        importDiagnosticsEnabled = (UserDefaults.standard.object(forKey: importDiagnosticsEnabledKey) as? Bool) ?? false

        loadImportLog()

        loadRecent()

        refresh()

        setupObservers()

    }

    /// 监听播放引擎的「曲目开始播放」通知，记录最近播放。

    private func setupObservers() {

        NotificationCenter.default.publisher(for: .trackPlayed)

            .sink { [weak self] n in

                guard let id = n.userInfo?["id"] as? UUID else { return }

                Task { @MainActor in self?.recordRecent(id) }

            }

            .store(in: &cancellables)

    }

    // MARK: - 派生数据

    var favoriteTracks: [Track] { tracks.filter { $0.isFavorite } }

    /// 首页「歌曲」页应展示的曲目：未加入任何歌单的曲目（即尚未被归档的曲目）。

    /// 用户选择「移动到歌单」后，曲目从首页消失，但仍可在对应歌单、歌手、专辑、我喜欢页找到。

    var libraryTracks: [Track] {

        let playlistIDs = Set(playlists.flatMap { $0.trackIDs })

        return tracks.filter { !playlistIDs.contains($0.id) }

    }

    /// 最近播放的曲目（按播放时间倒序）。

    var recentTracks: [Track] {

        recentIDs.compactMap { id in tracks.first(where: { $0.id == id }) }

    }

    func tracks(in playlist: Playlist) -> [Track] {

        let set = Set(playlist.trackIDs)

        return tracks.filter { set.contains($0.id) }

    }

    // MARK: - 重建曲库

    /// 重新扫描本地文件 + 重建播放列表。收藏状态从 favoriteIDs 回填。

    func refresh() {

        // 释放上一次 refresh 时持有的安全作用域，避免长期累积

        for u in accessedReferencedURLs { u.stopAccessingSecurityScopedResource() }

        accessedReferencedURLs.removeAll()

        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {

            tracks = visibleSamples()

            return

        }

        // 清理 dangling：

        // - imported 记录指向的文件已不存在（如重复导入产生的坏记录）

        // - referenced 记录的书签失效或原文件已被删除

        // 解决「列表出现重复且无法播放」的残留。

        var removedIDs: [UUID] = []

        for (id, rec) in records {

            switch rec.source {

            case .imported:

                let u = docs.appendingPathComponent(rec.urlString)

                if !fileManager.fileExists(atPath: u.path) {

                    records.removeValue(forKey: id)

                    removedIDs.append(id)

                }

            case .referenced:

                guard let bm = rec.bookmark else {

                    records.removeValue(forKey: id)

                    removedIDs.append(id)

                    continue

                }

                var stale = false

                do {

                    let resolved = try URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)

                    if stale || !fileManager.fileExists(atPath: resolved.path) {

                        records.removeValue(forKey: id)

                        removedIDs.append(id)

                    }

                } catch {

                    records.removeValue(forKey: id)

                    removedIDs.append(id)

                }

            case .remote, .sample:

                break

            }

        }

        if !removedIDs.isEmpty { saveRecords() }



        // 同步清理歌单里已不存在的曲目 id（引用原文件被外部删除后会留下 dangling id）。

        let validIDs = Set(records.values.map(\.id))

        var playlistsChanged = false

        for i in playlists.indices {

            let before = playlists[i].trackIDs.count

            playlists[i].trackIDs.removeAll { !validIDs.contains($0) }

            if playlists[i].trackIDs.count != before { playlistsChanged = true }

        }

        if playlistsChanged { savePlaylists() }



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

            case .referenced:

                guard let bm = record.bookmark else { continue }

                var stale = false

                let resolved: URL

                do {

                    resolved = try URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)

                } catch {

                    continue

                }

                let acc = resolved.startAccessingSecurityScopedResource()

                if acc { accessedReferencedURLs.insert(resolved) }

                userTracks.append(makeTrack(record: record, url: resolved, source: .referenced))

            case .sample:

                break

            }

        }

        userTracks.sort {

            $0.title.localizedStandardCompare($1.title) == .orderedAscending

        }

        tracks = visibleSamples() + userTracks

        // 清理已不存在的最近播放记录，避免指向已删除曲目

        let existing = Set(tracks.map(\.id))

        recentIDs = recentIDs.filter { existing.contains($0) }

    }

    /// 过滤掉被用户隐藏的示例曲

    private func visibleSamples() -> [Track] {

        Track.samples.filter { !hiddenSampleIDs.contains($0.id) }

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

            lyrics: record.lyrics,
            artwork: record.artwork.flatMap { UIImage(data: $0) }

        )

    }

    // MARK: - 导入

    /// 包装层：统一记录导入日志（触发/成功/失败 + 原文），再交给真正实现。

    /// 两条入口（onOpenURL 分享 / fileImporter 应用内）都走这里，日志一处覆盖。

    func importFile(from url: URL) async throws {

        let fileName = url.lastPathComponent

        noteImport(fileName, ok: true, message: "入口已触发，开始处理")

        do {

            try await importFileImpl(from: url)

            noteImport(fileName, ok: true, message: "成功：已写入曲库")

        } catch {

            noteImport(fileName, ok: false, message: error.localizedDescription)

            throw error

        }

    }

    /// 从 Files / Share Sheet 导入一个音频文件。

    /// - 引用模式（默认）：不复制，仅存安全书签，播放时直接读用户 Files 里的原文件（只占一份空间）。

    /// - 复制模式：拷进 App Documents（最稳，离线/后台可靠，但占 2 倍空间，可在设置切换）。

    /// 解析 ID3 / MP4 标签（标题/歌手/专辑/时长/内嵌歌词/封面），读不到则用文件名兜底。

    private func importFileImpl(from url: URL) async throws {

        let accessing = url.startAccessingSecurityScopedResource()

        defer { if accessing { url.stopAccessingSecurityScopedResource() } }



        // 统一去重指纹：源文件名 + 文件大小。复制/引用模式通用，避免同一文件反复导入产生多条记录。

        let srcSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        let fingerprint = "\(url.lastPathComponent)|\(srcSize)"



        // 先读标签（在源文件上读，引用/复制都通用）。

        let tags = await extractTags(from: url)

        let baseTitle = (url.lastPathComponent as NSString).deletingPathExtension

        let title = (tags.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? baseTitle

        let artist = (tags.artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"

        let album = tags.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let lyrics = tags.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)

        let artwork = compactArtwork(tags.artwork)

        // 查重：已有相同指纹（不论 imported/referenced）→ 更新路径/书签与元数据，不新增。

        if let existingID = records.first(where: { $0.value.fingerprint == fingerprint })?.key {

            if importByCopy {

                guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {

                    throw ImportError.noDocumentDir

                }

                let dest = uniqueURL(in: docs, for: url)

                do { try fileManager.copyItem(at: url, to: dest) } catch {

                    do { try coordinateCopy(from: url, to: dest) } catch {

                        throw ImportError.copyFailed(error.localizedDescription)

                    }

                }

                records[existingID] = TrackRecord(

                    id: existingID, title: title, artist: artist, album: album,

                    source: .imported, urlString: dest.lastPathComponent, coverSeed: dest.lastPathComponent,

                    lyrics: lyrics, bookmark: nil, fingerprint: fingerprint, artwork: artwork)

            } else {

                if let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {

                    records[existingID] = TrackRecord(

                        id: existingID, title: title, artist: artist, album: album,

                        source: .referenced, urlString: url.lastPathComponent, coverSeed: url.lastPathComponent,

                        lyrics: lyrics, bookmark: bm, fingerprint: fingerprint, artwork: artwork)

                } else {

                    // 引用书签失败 → 回退复制，并把旧记录转成 imported

                    guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {

                        throw ImportError.noDocumentDir

                    }

                    let dest = uniqueURL(in: docs, for: url)

                    do { try fileManager.copyItem(at: url, to: dest) } catch { try coordinateCopy(from: url, to: dest) }

                    records[existingID] = TrackRecord(

                        id: existingID, title: title, artist: artist, album: album,

                        source: .imported, urlString: dest.lastPathComponent, coverSeed: dest.lastPathComponent,

                        lyrics: lyrics, bookmark: nil, fingerprint: fingerprint, artwork: artwork)

                }

            }

            saveRecords(); refresh(); catalogVersion += 1

            reportImportResult("已更新（去重）：\(title)")

            return

        }



        // 无重复：按当前模式新增记录

        if !importByCopy {

            if let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {

                addReferencedRecord(bookmark: bm, fileName: url.lastPathComponent, title: title, artist: artist, album: album, lyrics: lyrics, fingerprint: fingerprint, artwork: artwork)

                reportImportResult("已引用（不复制）：\(title)")

                return

            }

            // 书签失败 → 回退复制

        }



        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {

            throw ImportError.noDocumentDir

        }

        let dest = uniqueURL(in: docs, for: url)

        do { try fileManager.copyItem(at: url, to: dest) } catch {

            do { try coordinateCopy(from: url, to: dest) } catch {

                throw ImportError.copyFailed(error.localizedDescription)

            }

        }

        addImportedRecord(filename: dest.lastPathComponent, title: title, artist: artist, album: album, lyrics: lyrics, fingerprint: fingerprint, artwork: artwork)

        reportImportResult("已导入：\(title)")

    }

    /// 用 NSFileCoordinator 在作用域内拷贝文件，兼容 security-scoped 资源

    /// （直接 copyItem 在跨 App 分享 / 重签名环境常因沙盒权限失败）。

    // MARK: - 文件夹批量扫描导入

    /// 扫描一个文件夹（含子目录）批量导入音频，强制复制到 App 沙盒，自动去重。
    /// 对应「识别文件夹内歌曲自动导入」：选一次文件夹，递归把所有音频收进曲库，不造成双倍存储
    /// （原文件留在用户 Files 里、App 沙盒内是自己的工作副本，符合强制复制策略）。
    @discardableResult
    func importFolder(at folderURL: URL) async -> (imported: Int, skipped: Int, failed: Int) {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            reportImportResult("导入失败：无法访问 App 文档目录")
            return (0, 0, 0)
        }

        let audioExts = Set(["mp3","m4a","aac","wav","flac","ogg","opus","wma","ape","aiff","caf","mp4","mov","m4v","mka","m4b","wv","tta"])

        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            reportImportResult("导入失败：无法读取所选文件夹")
            return (0, 0, 0)
        }

        var imported = 0, skipped = 0, failed = 0
        var newRecords: [TrackRecord] = []

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard audioExts.contains(ext) else { continue }

            let srcSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            let fingerprint = "\(fileURL.lastPathComponent)|\(srcSize)"

            if records.values.contains(where: { $0.fingerprint == fingerprint }) {
                skipped += 1
                continue
            }

            let dest = uniqueURL(in: docs, for: fileURL)
            do {
                try fileManager.copyItem(at: fileURL, to: dest)
            } catch {
                do { try coordinateCopy(from: fileURL, to: dest) }
                catch { failed += 1; continue }
            }

            let tags = await extractTags(from: fileURL)
            let baseTitle = (fileURL.lastPathComponent as NSString).deletingPathExtension
            let title = (tags.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? baseTitle
            let artist = (tags.artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"
            let album = tags.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lyrics = tags.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
            let artwork = compactArtwork(tags.artwork)

            let rec = TrackRecord(
                id: UUID(),
                title: title, artist: artist, album: album,
                source: .imported,
                urlString: dest.lastPathComponent,
                coverSeed: dest.lastPathComponent,
                lyrics: lyrics,
                bookmark: nil,
                fingerprint: fingerprint,
                artwork: artwork
            )
            newRecords.append(rec)
            imported += 1
        }

        if !newRecords.isEmpty {
            for r in newRecords { records[r.id] = r }
            saveRecords(); refresh(); catalogVersion += 1
        }

        let msg = "文件夹导入完成：新增 \(imported) 首，跳过重复 \(skipped) 首" + (failed > 0 ? "，失败 \(failed) 首" : "")
        reportImportResult(msg)
        noteImport(folderURL.lastPathComponent, ok: imported > 0, message: msg)
        return (imported, skipped, failed)
    }

    private func coordinateCopy(from source: URL, to dest: URL) throws {

        var coordinatorError: NSError?

        var innerError: NSError?

        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinatorError) { scopedURL in

            do {

                try FileManager.default.copyItem(at: scopedURL, to: dest)

            } catch {

                innerError = error as NSError

            }

        }

        if let e = coordinatorError ?? innerError { throw e }

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

            lyrics: nil,

            bookmark: nil,

            fingerprint: nil

        )

        records[id] = record

        saveRecords()

        refresh()

        catalogVersion += 1

    }

    /// 导入一个「歌单 JSON」：包含多首带直链音频 URL 的曲目。

    /// 策略：先按常见字段名提取曲目数组；若一条都提取不到，则全树递归扫描所有疑似音频的 http(s) URL 兜底，

    /// 最大限度兼容各种 JSON 结构。导入后自动建歌单（JSON 含 name/title 则用之命名，否则「导入歌单」）。

    /// 抛错仅发生在「完全没有任何可导入音频链接」时。

    func importPlaylist(from data: Data) throws -> Int {

        let parsed = try JSONSerialization.jsonObject(with: data)

        var playlistName: String?

        var items: [[String: Any]] = []

        if let dict = parsed as? [String: Any] {

            playlistName = firstString(dict, keys: ["name", "title", "playlist", "listName", "list_name", "歌单名", "名称"])

            items = dict.compactMap { key, value in

                (["tracks", "list", "songs", "data", "items", "musics", "歌曲", "歌单"].contains(key) ? value : nil)

            }

            .first(where: { $0 is [[String: Any]] }) as? [[String: Any]] ?? []

        } else if let arr = parsed as? [[String: Any]] {

            items = arr

        }

        var ids: [UUID] = []

        if !items.isEmpty {

            ids = importItems(items)

        }

        // 兜底：字段名路径一条都没抓到时，递归扫描整棵 JSON 找音频 URL

        if ids.isEmpty {

            let urls = collectAudioURLs(parsed)

            for u in urls {

                ids.append(addRemoteTrack(urlString: u, title: nil, artist: nil, album: nil))

            }

            if !ids.isEmpty {

                saveRecords(); refresh(); catalogVersion += 1

            }

        }

        if ids.isEmpty { throw ImportError.noTracks }

        let name = (playlistName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "导入歌单"

        let playlist = Playlist(name: name, trackIDs: ids)

        playlists.append(playlist)

        savePlaylists()

        catalogVersion += 1

        return ids.count

    }

    private func importItems(_ items: [[String: Any]]) -> [UUID] {

        var ids: [UUID] = []

        for item in items {

            guard let rawURL = firstString(item, keys: ["url", "src", "play_url", "playUrl", "audio", "link", "mp3", "file", "urlString", "songUrl", "音乐", "链接", "地址"]),

                  let url = URL(string: rawURL), url.scheme?.hasPrefix("http") == true else { continue }

            let title = firstString(item, keys: ["title", "name", "song", "songname", "musicName", "music_name", "歌曲", "歌名", "名称"])

                ?? url.deletingPathExtension().lastPathComponent

            let artist = firstString(item, keys: ["artist", "singer", "author", "singerName", "artistName", "歌手", "演唱"]) ?? "未知歌手"

            let album = firstString(item, keys: ["album", "albumName", "albumname", "专辑"]) ?? ""

            ids.append(addRemoteTrack(urlString: url.absoluteString, title: title, artist: artist, album: album))

        }

        if !ids.isEmpty {

            saveRecords(); refresh(); catalogVersion += 1

        }

        return ids

    }

    /// 新增一条远程曲目记录，返回其 id（不负责 save/refresh，由调用方统一处理）。

    private func addRemoteTrack(urlString: String, title: String?, artist: String?, album: String?) -> UUID {

        let id = UUID()

        let t = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

            ?? URL(string: urlString).flatMap { $0.deletingPathExtension().lastPathComponent } ?? "未知曲目"

        let a = (artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "未知歌手"

        let al = (album?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""

        let record = TrackRecord(

            id: id,

            title: t,

            artist: a,

            album: al,

            source: .remote,

            urlString: urlString,

            coverSeed: urlString,

            lyrics: nil,

            bookmark: nil,

            fingerprint: nil

        )

        records[id] = record

        return id

    }

    /// 递归遍历整棵 JSON，收集所有「疑似音频」的 http(s) 字符串（兜底解析用）。

    private func collectAudioURLs(_ value: Any) -> [String] {

        var out: [String] = []

        func dfs(_ v: Any) {

            if let s = v as? String {

                if isAudioURL(s) { out.append(s) }

            } else if let arr = v as? [Any] {

                arr.forEach(dfs)

            } else if let dict = v as? [String: Any] {

                dict.values.forEach(dfs)

            }

        }

        dfs(value)

        return out

    }

    private func isAudioURL(_ s: String) -> Bool {

        guard s.hasPrefix("http://") || s.hasPrefix("https://") else { return false }

        let pathExt = (URL(string: s)?.pathExtension ?? "").lowercased()

        let nonAudio = ["jpg", "jpeg", "png", "webp", "gif", "svg", "json", "html", "css", "js", "xml", "txt", "php"]

        if nonAudio.contains(pathExt) { return false }

        let audio = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "ape", "aiff", "caf"]

        if audio.contains(pathExt) { return true }

        // 无扩展名也接受（很多直链音频不带扩展名），仅排除已知的图片/文档后缀

        return true

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

    /// 删除/隐藏一条曲目：

    /// - 示例曲：不删文件，仅加入隐藏集合（持久化），下次刷新不再出现；

    /// - 引用原文件：不动用户原文件，仅移除记录并释放安全作用域；

    /// - 复制导入 / 远程：移除记录，复制模式同时删掉本地副本。

    func delete(track: Track) {

        if track.source == .sample {

            hiddenSampleIDs.insert(track.id)

            saveHiddenSamples()

            refresh()

            catalogVersion += 1

            return

        }

        if track.source == .referenced {

            track.url.stopAccessingSecurityScopedResource()

            accessedReferencedURLs.remove(track.url)

            // 引用记录删除后，安全作用域可能仍被同一 URL 的其他记录使用；refresh 会重新 startAccessing。

        } else if track.isLocalFile {

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

    /// 恢复所有被隐藏的示例曲

    func restoreSamples() {

        hiddenSampleIDs.removeAll()

        saveHiddenSamples()

        refresh()

        catalogVersion += 1

    }

    /// 释放所有已持有的引用原文件安全作用域（App 退出/进入后台前调用）

    func stopAllAccess() {

        for u in accessedReferencedURLs { u.stopAccessingSecurityScopedResource() }

        accessedReferencedURLs.removeAll()

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

    private func addImportedRecord(filename: String, title: String, artist: String, album: String, lyrics: String?, fingerprint: String?, artwork: Data? = nil) {

        let id = UUID()

        let record = TrackRecord(

            id: id,

            title: title,

            artist: artist,

            album: album,

            source: .imported,

            urlString: filename,

            coverSeed: filename,

            lyrics: lyrics,
            bookmark: nil,
            fingerprint: fingerprint, artwork: artwork

        )

        records[id] = record

        saveRecords()

        refresh()

        catalogVersion += 1

    }

    /// 引用原文件模式：存安全书签，不复制文件，播放时直接读用户原文件。

    private func addReferencedRecord(bookmark: Data, fileName: String, title: String, artist: String, album: String, lyrics: String?, fingerprint: String?, artwork: Data? = nil) {

        let id = UUID()

        let record = TrackRecord(

            id: id,

            title: title,

            artist: artist,

            album: album,

            source: .referenced,

            urlString: fileName,

            coverSeed: fileName,

            lyrics: lyrics,
            bookmark: bookmark,
            fingerprint: fingerprint, artwork: artwork

        )

        records[id] = record

        saveRecords()

        refresh()

        catalogVersion += 1

    }

    // MARK: - 自动归入歌单

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

        info.referencedCount = tracks.filter { $0.source == .referenced }.count

        info.hiddenSamples = hiddenSampleIDs.count

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

    /// 压缩封面图数据，限制最长边与体积，避免 UserDefaults 膨胀。
    private func compactArtwork(_ data: Data?) -> Data? {
        guard let data = data, let img = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 300
        if img.size.width <= maxSide && img.size.height <= maxSide { return data }
        let scale = min(maxSide / img.size.width, maxSide / img.size.height)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        img.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized?.jpegData(compressionQuality: 0.8)
    }

    // MARK: - 持久化

    private func loadImportLog() {

        guard let data = UserDefaults.standard.data(forKey: importLogKey),

              let list = try? JSONDecoder().decode([ImportLogEntry].self, from: data) else { return }

        importLog = list

    }

    private func recordRecent(_ id: UUID) {

        recentIDs.removeAll { $0 == id }

        recentIDs.insert(id, at: 0)

        if recentIDs.count > 50 { recentIDs.removeLast() }

        saveRecent()

    }

    private func saveRecent() {

        if let data = try? JSONEncoder().encode(recentIDs) {

            UserDefaults.standard.set(data, forKey: recentKey)

        }

    }

    private func loadRecent() {

        guard let data = UserDefaults.standard.data(forKey: recentKey),

              let list = try? JSONDecoder().decode([UUID].self, from: data) else { return }

        recentIDs = list

    }

    private func saveImportLog() {

        if let data = try? JSONEncoder().encode(importLog) {

            UserDefaults.standard.set(data, forKey: importLogKey)

        }

    }

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

    private func loadHiddenSamples() {

        guard let data = UserDefaults.standard.data(forKey: hiddenSamplesKey),

              let list = try? JSONDecoder().decode([UUID].self, from: data) else { return }

        hiddenSampleIDs = Set(list)

    }

    private func saveHiddenSamples() {

        if let data = try? JSONEncoder().encode(Array(hiddenSampleIDs)) {

            UserDefaults.standard.set(data, forKey: hiddenSamplesKey)

        }

    }

}

