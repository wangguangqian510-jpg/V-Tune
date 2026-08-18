import WidgetKit
import SwiftUI

// MARK: - 灵动岛 Widget（就绪待启用）
//
// 重要：当前企业签名描述文件 `CycommGroupAppProfile` 的 application-identifier 为精确匹配
// `4TDEWHFV5T.com.aramco.cycomm`（非通配 `4TDEWHFV5T.*`）。Widget 扩展必须有自己的 Bundle ID
// （如 `com.aramco.cycomm.JukeboxWidget`），而该 ID 不在当前描述文件内，zsign 无法签名，会导致
// 整个 IPA 构建/签名失败。因此本文件**暂未加入 Xcode target / pbxproj**，不影响当前构建。
//
// 启用步骤（待更换为通配描述文件，或在 Apple Developer 给当前描述文件新增
// `com.aramco.cycomm.JukeboxWidget` 后）：
//   1. 在 Xcode 新增 Widget Extension target（Bundle ID = com.aramco.cycomm.JukeboxWidget）；
//   2. 把本文件加入该 target 的 Sources；
//   3. 在 App 的 Info.plist 确保 NSSupportsLiveActivities=true（已加）；
//   4. 重新构建。届时 PlayerEngine 中的 Live Activity 请求即会由本 Widget 渲染到灵动岛。
//
// 注：属性定义在此处独立一份，启用时与 PlayerEngine.swift 中的 JukeboxLiveActivityAttributes 保持一致。

@available(iOS 16.1, *)
struct JukeboxLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        var elapsed: Double
        var duration: Double
        var currentLine: String
    }
    var title: String
    var artist: String
}

@available(iOS 16.1, *)
struct JukeboxWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JukeboxLiveActivityAttributes.self) { context in
            // 锁屏 / 通知中心 全屏展示
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.attributes.title).font(.headline)
                    Spacer()
                    Text(context.attributes.artist).font(.subheadline).foregroundColor(.secondary)
                }
                Text(context.state.currentLine.isEmpty ? "♪" : context.state.currentLine)
                    .font(.body)
                    .lineLimit(1)
                ProgressView(value: context.state.elapsed, total: max(context.state.duration, 1))
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "music.note")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentLine.isEmpty ? "♪" : context.state.currentLine)
                        .lineLimit(1)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.elapsed, total: max(context.state.duration, 1))
                        .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            } minimal: {
                Image(systemName: "music.note")
            }
            .widgetURL(URL(string: "jukebox://nowplaying"))
        }
    }
}
