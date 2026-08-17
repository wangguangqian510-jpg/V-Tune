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

/// 异步提取音频标签：标题 / 歌手 / 专辑 / 时长 / 内嵌歌词（ID3 USLT、iTunes ©lyr、AVAsset.lyrics）/ 内嵌封面。
/// 思路参考成熟播放器的本地导入实现，此处为自写版本，仅用 AVFoundation，不依赖任何第三方库。
func extractTags(from url: URL) async -> AudioFileTags {
    let asset = AVURLAsset(url: url)
    var result = AudioFileTags()

    // 时长
    if let d = try? await asset.load(.duration) {
        let secs = CMTimeGetSeconds(d)
        if secs.isFinite, secs > 0 { result.duration = secs }
    }

    // 公共元数据：标题 / 歌手 / 专辑 / 封面
    let metadata = (try? await asset.load(.metadata)) ?? []
    for item in metadata {
        if let commonKey = item.commonKey?.rawValue {
            switch commonKey {
            case AVMetadataKey.commonKeyTitle.rawValue:
                result.title = (try? await item.load(.stringValue)) ?? result.title
            case AVMetadataKey.commonKeyArtist.rawValue:
                result.artist = (try? await item.load(.stringValue)) ?? result.artist
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                result.album = (try? await item.load(.stringValue)) ?? result.album
            case AVMetadataKey.commonKeyArtwork.rawValue:
                if let data = try? await item.load(.dataValue) { result.artwork = data }
            default:
                break
            }
        }
        // 歌词：ID3 USLT / SYLT、iTunes ©lyr、含 "lyric"/"uslt" 的键
        if result.lyrics == nil {
            var hit = false
            if let id = item.identifier?.rawValue.lowercased() {
                if id.contains("uslt") || id.contains("sylt") || id.contains("lyric") || id.contains("lyr") {
                    hit = true
                }
            }
            if !hit, let key = item.key as? String, key.lowercased().contains("lyric") || key.lowercased().contains("uslt") {
                hit = true
            }
            if hit, let text = try? await item.load(.stringValue), !text.isEmpty {
                result.lyrics = text
            }
        }
    }

    // AVAsset 直接提供的歌词（部分格式可用）
    if result.lyrics == nil {
        if let l = try? await asset.load(.lyrics), !l.isEmpty {
            result.lyrics = l
        }
    }

    // 封面过大时压缩到 300px，避免持久化体积膨胀
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
