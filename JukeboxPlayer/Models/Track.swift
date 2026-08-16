import Foundation
import SwiftUI

/// 一首曲目的数据模型。封面用渐变色表示，避免依赖外部图片资源。
struct Track: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let url: URL
    let cover: [Color]

    /// 示例播放列表：使用公开可访问的 Sample MP3（SoundHelix），方便直接运行体验。
    /// 实际使用时把 url 换成你自己的本地或远程音频地址即可。
    static let samples: [Track] = [
        Track(title: "Song One",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3")!, cover: [.blue, .purple]),
        Track(title: "Song Two",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3")!, cover: [.pink, .orange]),
        Track(title: "Song Three", artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3")!, cover: [.teal, .green]),
        Track(title: "Song Four",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3")!, cover: [.indigo, .cyan]),
        Track(title: "Song Five",  artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3")!, cover: [.red, .yellow]),
        Track(title: "Song Six",   artist: "SoundHelix", album: "Demo Album", url: URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3")!, cover: [.mint, .blue]),
    ]
}
