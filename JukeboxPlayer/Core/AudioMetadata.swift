import Foundation
import AVFoundation
import UIKit

/// 本地音频文件的 ID3 / MP4 元数据（同步读取，仅用于导入时解析）。
struct AudioFileTags {
    var title: String?
    var artist: String?
    var album: String?
    var lyrics: String?
}

/// 同步读取音频标签：AVFoundation 的元数据加载是异步的，这里用信号量
/// 转成同步调用，导入时短暂阻塞主线程即可（本地文件解析很快）。
func readAudioTags(from url: URL) -> AudioFileTags {
    let asset = AVURLAsset(url: url)
    var result = AudioFileTags(title: nil, artist: nil, album: nil, lyrics: nil)
    let group = DispatchGroup()
    group.enter()
    asset.loadValuesAsynchronously(forKeys: ["commonMetadata"]) {
        if asset.statusOfValue(forKey: "commonMetadata", error: nil) == .loaded {
            for item in asset.commonMetadata {
                switch item.commonKey {
                case .commonKeyTitle:      result.title = asTagString(item.value)
                case .commonKeyAlbumName:  result.album = asTagString(item.value)
                case .commonKeyArtist:     result.artist = asTagString(item.value)
                default:
                    // 歌词：部分 SDK 的 AVMetadataKey 没有 commonKeyLyrics 成员，
                    // 用原始键名做字符串兜底匹配（commonMetadata / USLT 等）。
                    let keyText = String(describing: item.commonKey ?? item.key).lowercased()
                    if keyText.contains("lyric") || keyText == "uslt" {
                        result.lyrics = asTagString(item.value)
                    }
                }
            }
            // 再兜底扫一遍全部元数据格式（含 iTunes 私有的 USLT 等）
            if result.lyrics == nil {
                for item in asset.metadata {
                    let keyText = String(describing: item.commonKey ?? item.key).lowercased()
                    if keyText.contains("lyric") || keyText == "uslt" {
                        result.lyrics = asTagString(item.value)
                        break
                    }
                }
            }
        }
        group.leave()
    }
    group.wait()
    return result
}

/// 把元数据值统一成非空的字符串（兼容 String / Data(UTF-8)）。
private func asTagString(_ value: Any?) -> String? {
    if let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
    if let d = value as? Data,
       let s = String(data: d, encoding: .utf8),
       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
    return nil
}
