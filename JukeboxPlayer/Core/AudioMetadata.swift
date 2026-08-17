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
                case .commonKeyTitle:      result.title = item.value as? String
                case .commonKeyAlbumName:  result.album = item.value as? String
                case .commonKeyArtist:     result.artist = item.value as? String
                case .commonKeyLyrics:
                    if let s = item.value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.lyrics = s
                    } else if let d = item.value as? Data,
                              let s = String(data: d, encoding: .utf8),
                              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.lyrics = s
                    }
                default: break
                }
            }
        }
        group.leave()
    }
    group.wait()
    return result
}
