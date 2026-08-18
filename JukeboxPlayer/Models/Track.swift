import Foundation

import SwiftUI



/// 曲目来源

enum TrackSource: String, Codable {

    case sample

    case imported

    case remote

    /// 引用原文件（不复制）：仅存安全书签，播放时直接读用户 Files 里的原文件

    case referenced

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

    let isFavorite: Bool

    /// 内嵌歌词 / 侧载歌词（LRC 或纯文本），无则为 nil

    let lyrics: String?



    /// 内嵌/导入时提取的封面图（专辑图），无则为 nil
    let artwork: UIImage?

    init(id: UUID = UUID(), title: String, artist: String, album: String = "", url: URL, cover: [Color], source: TrackSource, isFavorite: Bool = false, lyrics: String? = nil, artwork: UIImage? = nil) {

        self.id = id

        self.title = title

        self.artist = artist

        self.album = album

        self.url = url

        self.cover = cover

        self.source = source

        self.isFavorite = isFavorite

        self.lyrics = lyrics
        self.artwork = artwork

    }



    /// 是否来自本地文件系统

    var isLocalFile: Bool { url.isFileURL }



    /// 是否允许用户从曲库移除（示例曲也可移除/隐藏，但只隐藏不删文件）

    var isRemovable: Bool { true }



    /// 示例播放列表：使用公开可访问的 Sample MP3（SoundHelix），方便直接运行体验。

    /// 注意：id 必须固定（不能用 UUID() 默认随机），否则「隐藏示例曲」的持久化集合跨启动会失效。

    static let samples: [Track] = [

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,

              title: "Song One",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!, cover: [.blue, .purple], source: .sample),

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111102")!,

              title: "Song Two",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3")!, cover: [.pink, .orange], source: .sample),

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111103")!,

              title: "Song Three", artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3")!, cover: [.teal, .green], source: .sample),

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111104")!,

              title: "Song Four",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3")!, cover: [.indigo, .cyan], source: .sample),

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111105")!,

              title: "Song Five",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3")!, cover: [.red, .yellow], source: .sample),

        Track(id: UUID(uuidString: "11111111-1111-1111-1111-111111111106")!,

              title: "Song Six",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3")!, cover: [.mint, .blue], source: .sample),

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

