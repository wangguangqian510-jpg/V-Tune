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
/// 关键：带 6 秒超时保护。某些 mp3 在 iOS 上 AVAsset 同步读元数据会永久挂起，
/// 超时则退回空标签（导入仍成功、用文件名兜底），避免「导入不进」。
///
/// 之前版本的超时任务返回的是 `nil`，被 `if let r = result` 跳过，`group.cancelAll()`
/// 永远不执行，`for await` 会一直等那个挂死的读任务 → `importFile` 卡死、
/// 文件复制了但记录没建 → 列表空、无法导入。修复：超时返回**非空占位**，
/// 让循环能 break 并取消读取任务；同时把同步读放到全局并发队列，避免拖垮 Swift 协作线程池。
func extractTags(from url: URL) async -> AudioFileTags {
    await withTaskGroup(of: AudioFileTags?.self) { group in
        // 同步阻塞读：放到全局队列，绝不占用并发协作线程。
        group.addTask {
            await withCheckedContinuation { (cont: CheckedContinuation<AudioFileTags?, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: readTagsSync(from: url))
                }
            }
        }
        // 6 秒超时：返回非空占位（空标签），使下面循环能 break 并取消读取任务。
        group.addTask {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            return AudioFileTags()
        }
        var result: AudioFileTags = AudioFileTags()
        for await r in group {
            if let r = r {        // 先完成者（真实标签或超时占位）胜出
                result = r
                break
            }
        }
        group.cancelAll()
        return result
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
