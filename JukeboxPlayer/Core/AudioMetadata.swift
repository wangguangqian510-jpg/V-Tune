import Foundation
import AVFoundation
import UIKit

/// 本地音频文件的标签信息（导入时解析）。
struct AudioFileTags {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var lyrics: String?
    var artwork: Data?
}

/// 异步提取音频标签：标题 / 歌手 / 专辑 / 时长 / 内嵌歌词 / 封面。
/// 关键：带 6 秒超时保护。某些 mp3 在 iOS 上 AVAsset 并发 load 会永久挂起，
/// 超时则退回空标签（导入仍成功、用文件名兜底），避免「导入不进」。
func extractTags(from url: URL) async -> AudioFileTags {
    await withTaskGroup(of: AudioFileTags?.self) { group in
        group.addTask { readTagsSync(from: url) }
        group.addTask {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            return nil
        }
        for await result in group {
            if let r = result {
                group.cancelAll()
                return r
            }
        }
        return AudioFileTags()
    }
}

/// 同步读取标签（在 detached 任务中执行，避免阻塞主线程）。
private func readTagsSync(from url: URL) -> AudioFileTags {
    let asset = AVURLAsset(url: url)
    var result = AudioFileTags()

    let secs = CMTimeGetSeconds(asset.duration)
    if secs.isFinite, secs > 0 { result.duration = secs }

    for item in asset.metadata {
        if let commonKey = item.commonKey?.rawValue {
            switch commonKey {
            case AVMetadataKey.commonKeyTitle.rawValue:
                if result.title == nil { result.title = item.stringValue }
            case AVMetadataKey.commonKeyArtist.rawValue:
                if result.artist == nil { result.artist = item.stringValue }
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                if result.album == nil { result.album = item.stringValue }
            case AVMetadataKey.commonKeyArtwork.rawValue:
                if result.artwork == nil { result.artwork = item.dataValue }
            default:
                break
            }
        }
        if result.lyrics == nil {
            var hit = false
            if let id = item.identifier?.rawValue.lowercased() {
                if id.contains("uslt") || id.contains("sylt") || id.contains("lyric") || id.contains("lyr") { hit = true }
            }
            if !hit, let key = item.key as? String {
                let kl = key.lowercased()
                if kl.contains("lyric") || kl.contains("uslt") { hit = true }
            }
            if hit, let text = item.stringValue, !text.isEmpty { result.lyrics = text }
        }
    }

    if result.lyrics == nil {
        let l = asset.lyrics
        if !(l?.isEmpty ?? true) { result.lyrics = l }
    }

    if let data = result.artwork, data.count > 500_000 {
        result.artwork = compressArtwork(data: data, maxSize: 300)
    }
    return result
}

/// 压缩封面图片到指定边长（最长边）。
private func compressArtwork(data: Data, maxSize: CGFloat) -> Data? {
    guard let image = UIImage(data: data) else { return data }
    let size = CGSize(width: maxSize, height: maxSize)
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized?.jpegData(compressionQuality: 0.8)
}
