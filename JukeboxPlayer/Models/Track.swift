import Foundation
import SwiftUI

/// 曲目来源
enum TrackSource: String, Codable {
    case sample
    case imported
    case remote
}

/// 一首曲目的数据模型。封面用渐变色表示，避免依赖外部图片资源。
struct Track: Identifiable, Hashable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let url: URL
    let cover: [Color]
    let source: TrackSource

    init(id: UUID = UUID(), title: String, artist: String, album: String = "", url: URL, cover: [Color], source: TrackSource) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.url = url
        self.cover = cover
        self.source = source
    }

    /// 是否来自本地文件系统
    var isLocalFile: Bool { url.isFileURL }

    /// 是否允许用户删除（示例曲不可删）
    var isRemovable: Bool { source != .sample }

    /// 示例播放列表：使用公开可访问的 Sample MP3（SoundHelix），方便直接运行体验。
    static let samples: [Track] = [
        Track(title: "Song One",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!, cover: [.blue, .purple], source: .sample),
        Track(title: "Song Two",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3")!, cover: [.pink, .orange], source: .sample),
        Track(title: "Song Three", artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3")!, cover: [.teal, .green], source: .sample),
        Track(title: "Song Four",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3")!, cover: [.indigo, .cyan], source: .sample),
        Track(title: "Song Five",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3")!, cover: [.red, .yellow], source: .sample),
        Track(title: "Song Six",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3")!, cover: [.mint, .blue], source: .sample),
    ]
}

/// 根据字符串生成一对稳定的渐变色，用作本地/远程曲目的默认封面。
func coverColors(for string: String) -> [Color] {
    let palette: [Color] = [
        .blue, .purple, .pink, .orange, .red, .yellow,
        .green, .teal, .indigo, .cyan, .mint
    ]
    var hasher = Hasher()
    hasher.combine(string)
    let hash = abs(hasher.finalize())
    let i = hash % palette.count
    return [palette[i], palette[(i + 3) % palette.count]]
}
