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

/// 管理示例曲 + 用户导入的本地/远程音频。
/// 本地音频复制到 App Documents 目录，元数据用 JSON 存 UserDefaults。
@MainActor
final class TrackStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []

    private let fileManager = FileManager.default
    private let recordsKey = "JukeboxTrackRecords_v1"
    private var records: [UUID: TrackRecord] = [:]

    init() {
        loadRecords()
        refresh()
    }

    /// 重新扫描本地文件 + 重建播放列表
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
                userTracks.append(Track(
                    id: record.id,
                    title: record.title,
                    artist: record.artist,
                    album: record.album,
                    url: url,
                    cover: coverColors(for: record.coverSeed),
                    source: .imported
                ))
            case .remote:
                guard let url = URL(string: record.urlString) else { continue }
                userTracks.append(Track(
                    id: record.id,
                    title: record.title,
                    artist: record.artist,
                    album: record.album,
                    url: url,
                    cover: coverColors(for: record.coverSeed),
                    source: .remote
                ))
            case .sample:
                break
            }
        }

        userTracks.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        tracks = Track.samples + userTracks
    }

    /// 从 Files / Share Sheet 导入一个音频文件到 App Documents。
    func importFile(from url: URL) throws {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dest = uniqueURL(in: docs, for: url)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try fileManager.copyItem(at: url, to: dest)

        addImportedRecord(filename: dest.lastPathComponent)
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
    }

    /// 删除一条本地或远程曲目
    func delete(track: Track) {
        guard track.isRemovable else { return }
        if track.isLocalFile {
            try? fileManager.removeItem(at: track.url)
        }
        records.removeValue(forKey: track.id)
        saveRecords()
        refresh()
    }

    private func addImportedRecord(filename: String) {
        let id = UUID()
        let title = (filename as NSString).deletingPathExtension
        let record = TrackRecord(
            id: id,
            title: title,
            artist: "本地音频",
            album: "",
            source: .imported,
            urlString: filename,
            coverSeed: filename
        )
        records[id] = record
        saveRecords()
        refresh()
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
}
