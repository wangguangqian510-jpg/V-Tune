# Jukebox 播放器（iOS）

基于 GitHub 开源项目 [teodorpatras/Jukebox](https://github.com/teodorpatras/Jukebox)（MIT 协议）开发的 iOS 音乐播放器。
原库是 2016 年的 Swift 3 代码，本项目将其**核心移植为现代 Swift（Swift 5.9+ / iOS 16+）**，并在其上用 **SwiftUI** 实现了一套完整播放器 UI。

> 注意：当前仓库是在无 macOS 环境下生成的源码工程。代码已按现代 Swift 逐一排查编译要点（AVAudioSession 新 API、`MPMediaItemArtwork` 新初始化器、`AVMetadataKey` 枚举、@objc 通知、`CMTime` 处理、actor 隔离等），但**首次请在 Xcode 中打开并编译验证**。

## 功能

- 本地 / 远程（HTTP/HTTPS 流媒体）音频播放，基于 `AVPlayer`
- 播放列表：播放 / 暂停 / 上一首 / 下一首 / 进度拖拽 / 音量调节
- 锁屏与控制中心（`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`），支持耳机线控、进度拖动
- 后台音频播放（`AVAudioSession` 设为 `playback` + `UIBackgroundModes: audio`）
- 自动读取音频元数据（标题 / 艺术家 / 专辑 / 封面）并在锁屏展示
- 渐变色封面（无需额外图片资源），迷你播放条 + 全屏播放页 + 播放队列

## 运行要求

- macOS + Xcode 15 及以上
- 目标设备 iOS 16.0+（真机或模拟器均可；后台音频建议在真机体验）

## 如何运行

1. 把整个 `JukeboxPlayer` 文件夹拷贝到 Mac。
2. 双击 `JukeboxPlayer.xcodeproj` 用 Xcode 打开。
3. 选中 `JukeboxPlayer` target → **Signing & Capabilities**：
   - 选择你的开发团队（Team）
   - 将 `Bundle Identifier` 改成你自己的（如 `com.yourname.JukeboxPlayer`）
4. 连接 iPhone（或选模拟器），点击运行 ▶。
   - 首次播放需要联网加载示例音频。
   - HTTP 流媒体已在 `Info.plist` 中放开 `NSAllowsArbitraryLoads`。

> 如果 `.xcodeproj` 在你的 Xcode 版本下打不开（极少数情况），最稳妥的办法：
> 新建一个 **iOS App（Interface: SwiftUI，Language: Swift）** 工程，把 `JukeboxPlayer/` 下的 `App`、`Models`、`Views`、`Core`、`Resources`、`Assets.xcassets` 整个拖进工程，
> 删除新建工程自带的 `ContentView.swift` / `Assets.xcassets` 冲突文件，并确认 `Info.plist` 含 `UIBackgroundModes: audio`。

## 换成你自己的歌单

编辑 `JukeboxPlayer/Models/Track.swift`：

```swift
static let samples: [Track] = [
    Track(title: "歌曲名",
          artist: "艺术家",
          album: "专辑",
          url: URL(string: "https://你的音频地址.mp3")!,
          cover: [.blue, .purple]),   // 封面渐变色
    // 继续添加……
]
```

- `url` 支持本地文件（`Bundle.main.url(forResource:ofType:)`）或远程地址。
- 远程音频若带 ID3 元数据，会被自动读取并显示；无元数据则回退到 `title`。

## 目录结构

```
JukeboxPlayer/
├── JukeboxPlayer.xcodeproj       # 工程文件（脚本生成）
├── README.md
├── generate_project.py           # 用于重新生成 .xcodeproj 的脚本
└── JukeboxPlayer/
    ├── App/
    │   ├── JukeboxPlayerApp.swift  # @main 入口，加载示例歌单
    │   └── PlayerEngine.swift      # 封装 Jukebox，桥接 SwiftUI + 远程控制
    ├── Models/
    │   └── Track.swift             # 曲目模型 + 示例歌单
    ├── Views/
    │   ├── ContentView.swift        # 导航 + 底部迷你条
    │   ├── LibraryView.swift        # 曲库列表
    │   ├── TrackRow.swift          # 单行 + 律动条
    │   ├── NowPlayingBar.swift      # 迷你播放条
    │   └── NowPlayingView.swift     # 全屏播放页 + 队列
    ├── Core/
    │   └── Jukebox.swift            # 移植后的播放核心（Jukebox + JukeboxItem）
    ├── Resources/
    │   └── Info.plist               # 含后台音频模式
    └── Assets.xcassets/             # AppIcon / AccentColor（请补充图标）
```

## 架构说明

- **Core/Jukebox.swift**：从原库移植的播放引擎，对外暴露 `play/pause/stop/seek/playNext/playPrevious` 等 API 与 `JukeboxDelegate` 回调。
- **App/PlayerEngine.swift**：`@MainActor` 的 `ObservableObject`，持有 `Jukebox` 实例，把回调同步为 SwiftUI 可观察状态，并接入 `MPRemoteCommandCenter`。
- **Views**：纯 SwiftUI 展示层，通过 `environmentObject` 消费 `PlayerEngine`。

## 协议 / 致谢

- 播放核心移植自 [teodorpatras/Jukebox](https://github.com/teodorpatras/Jukebox)，原版权归 Teodor Patraş 所有，采用 **MIT License**。
- 本工程在此基础上做了现代 Swift 适配与 SwiftUI 界面，可自由用于学习与非商业用途；若用于发布请遵守 MIT 协议并保留原版权声明。
