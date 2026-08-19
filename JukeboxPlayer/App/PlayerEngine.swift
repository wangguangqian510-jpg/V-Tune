import Foundation

import Combine

import UIKit

import SwiftUI

import MediaPlayer

import AVFoundation

import AudioToolbox
import ActivityKit

/// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机

enum PlaybackMode: String, CaseIterable {

    case order

    case loop

    case single

    case shuffle

}

/// 灵动岛 / Live Activity 属性（主 App 与 Widget 扩展共用一份定义）。
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

/// 播放引擎：基于 AVPlayer 直连（本地文件与远程 URL 走同一条路），

/// 桥接到 SwiftUI（ObservableObject），并接入 MPRemoteCommandCenter（锁屏 / 控制中心 / 耳机线控）。

///

/// 设计要点（参考成熟播放器的做法，自写实现，避免第三方封装的脆弱逻辑）：

/// - 单 AVPlayer + 单 AVPlayerItem，上一首/下一首时整体替换 item，不依赖队列播放器。

/// - `load` 仅在曲目列表 id 集合变化时才更新导航列表，绝不重建正在播放的 player，避免点歌重置。

/// - 远程音频（如 SoundHelix 直链）与本地文件走完全相同的 AVPlayer 路径，能否出声只取决于网络/文件可达。

@MainActor

final class PlayerEngine: ObservableObject {

    @Published private(set) var tracks: [Track] = []

    @Published private(set) var currentIndex: Int = 0

    @Published private(set) var isPlaying: Bool = false

    @Published private(set) var currentTime: Double = 0
    /// 实时播放进度（直接读 AVPlayer，供黑胶旋转用），不受 currentTime 发布节流影响。
    var liveCurrentTime: Double { player?.currentTime().seconds ?? 0 }

    @Published private(set) var duration: Double = 0

    @Published private(set) var title: String = "未在播放"

    @Published private(set) var artist: String = ""

    @Published private(set) var album: String = ""

    @Published private(set) var artwork: UIImage?

    @Published private(set) var lyrics: String?

    /// 锁屏歌词：记录上一次推送到 MPNowPlayingInfoCenter 的歌词行，只在变化时刷新。
    private var lastLyricLine: String = ""

    /// 锁屏占位封面缓存：曲目无内嵌封面时，用 currentCover 渐变色合成一张 600×600 图当占位
    /// （避免 iOS 18 因缺 artwork 把所有控制置灰）。
    private var cachedPlaceholderArtwork: UIImage?
    private var cachedPlaceholderKey: String = ""

    /// 播放失败后是否已做一次性 session 重试（成功切歌时重置为 false）。
    private var sessionRetried = false

    /// 当前曲目是否为视频文件（MP4/MOV 等），由 setupAndPlay 检测，用于切换视频播放界面。

    @Published var isVideo: Bool = false

    @Published private(set) var isLoading: Bool = false

    @Published private(set) var lastError: String?

    /// 用户正在拖动进度条时为 true：期间周期观察器不回写 currentTime，避免与滑块互相打架。

    @Published var isScrubbing: Bool = false

    @Published var volume: Float = 1.0 {

        didSet { player?.volume = volume }

    }

    /// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机

    @Published var playbackMode: PlaybackMode = .order

    // MARK: - 播放增强：睡眠定时 / 播放速度 / 歌词偏移

    /// 睡眠定时剩余秒数（0 = 未设置），UI 用于倒计时显示。

    @Published private(set) var sleepRemaining: Int = 0

    private var sleepTimer: Timer?

    /// 播放速度 0.5×–2×，应用到 AVPlayer.rate。

    @Published var playbackRate: Float = 1.0 {

        didSet { player?.rate = playbackRate }

    }

    /// 歌词时间轴整体偏移（秒，可正可负），校准 LRC 与音频不同步。

    @Published var lyricsOffset: Double = 0 {

        didSet { UserDefaults.standard.set(lyricsOffset, forKey: lyricsOffsetKey) }

    }

    private let lyricsOffsetKey = "JukeboxLyricsOffset_v1"

    // MARK: - EQ 音效（默认关闭，避免影响基础播放稳定性）

    private let eqEnabledKey = "JukeboxEQEnabled_v1"

    private let eqBandsKey = "JukeboxEQBands_v1"

    private let eqPresetKey = "JukeboxEQPreset_v1"

    @Published var eqEnabled: Bool = false {

        didSet {

            UserDefaults.standard.set(eqEnabled, forKey: eqEnabledKey)

            // 开启时若还没任何增益（全 0），自动选择「默认」平直曲线，保证稳定、不改变原始听感。

            if eqEnabled, eqBands.allSatisfy({ $0 == 0 }) {

                selectPreset("默认")

            } else {

                applyEQToCurrentItem()

            }

        }

    }

    /// 当前生效的 10 段增益（dB），由预设填充或被图形化滑块修改。

    /// 关键修复：didSet 只把新增益喂给已存在的 tap（不重建 audioMix / 不 replaceCurrentItem），

    /// 否则拖动 10 段滑块会连续触发 replaceCurrentItem，把 AVPlayer 反复替换导致卡死/静音。

    @Published var eqBands: [Double] = Array(repeating: 0, count: EQAudioTap.bandCount) {

        didSet {

            UserDefaults.standard.set(eqBands, forKey: eqBandsKey)

            // 滑块拖动后，自动把 preset 名同步为匹配预设或「自定义」。

            eqPreset = EQAudioTap.presets.first { $0.value == eqBands }?.key ?? "自定义"

            updateEQBandsOnly()

        }

    }

    /// UI 选中的预设名。默认「默认」平直曲线；拖动滑块不匹配任何预设时显示「自定义」。

    @Published var eqPreset: String = "默认" {

        didSet { UserDefaults.standard.set(eqPreset, forKey: eqPresetKey) }

    }

    /// EQ 诊断文字（播放页展示用，确认 tap 是否真的在处理音频）

    @Published var eqDiagnostic: String = "均衡器已关闭"

    private let eqTap = EQAudioTap()

    private var processingTap: MTAudioProcessingTap?

    /// 选中一个预设：填充 eqBands 并立即应用。

    func selectPreset(_ name: String) {

        guard let b = EQAudioTap.presets[name] else { return }

        eqPreset = name

        eqBands = b   // 触发 didSet -> 持久化 + applyEQ

    }

    private var player: AVPlayer?

    private var playerItem: AVPlayerItem?

    /// 暴露底层 AVPlayer 给视频播放界面（VideoPlayer）复用，避免重复创建播放器。

    var avPlayer: AVPlayer? { player }

    private var timeObserver: Any?

    private var cancellables = Set<AnyCancellable>()

    /// 灵动岛 Live Activity 的 id（iOS 16.1+；UI 由 Widget 扩展提供）。
    private var liveActivityID: String? = nil

    /// 灵动岛定时刷新（每 5 秒同步一次进度/歌词行，避免高频推送）。
    private var liveActivityTimer: Timer?

    init() {

        setupAudioSession()

        setupRemoteCommands()

        setupNotifications()

        loadPersistedState()

    }

    /// 加载持久化的 EQ / 歌词偏移状态。睡眠定时每次启动清零，不持久化。

    private func loadPersistedState() {

        if let saved = UserDefaults.standard.array(forKey: eqBandsKey) as? [Double], saved.count == EQAudioTap.bandCount {

            eqBands = saved

        }

        // 以实际保存的 bands 为准反推预设名，避免上次是「自定义」却显示旧预设名。

        eqPreset = EQAudioTap.presets.first { $0.value == eqBands }?.key

            ?? (UserDefaults.standard.string(forKey: eqPresetKey) ?? "默认")

        eqEnabled = UserDefaults.standard.bool(forKey: eqEnabledKey)

        lyricsOffset = UserDefaults.standard.object(forKey: lyricsOffsetKey) as? Double ?? 0

    }

    // MARK: - 播放列表

    /// 更新导航用的曲目列表。仅当 id 集合变化时才更新，保持正在播放的状态不被打断。

    func load(_ newTracks: [Track]) {

        let sameIDs = newTracks.map(\.id) == tracks.map(\.id)

        if sameIDs { return }

        let previousID = tracks[safe: currentIndex]?.id

        tracks = newTracks

        if let prev = previousID, let idx = newTracks.firstIndex(where: { $0.id == prev }) {

            currentIndex = idx

        } else {

            currentIndex = newTracks.isEmpty ? 0 : min(currentIndex, newTracks.count - 1)

            // 当前播放的曲目被从曲库移除，停止播放并清理状态，避免「删了还在响」。

            if previousID != nil {

                stopAndClear()

            }

        }

        // 不重建 player：当前曲目若仍存在，AVPlayer 仍在播同一份 URL。

    }

    var hasTrack: Bool { player != nil }

    var currentCover: [Color] {

        if let track = tracks[safe: currentIndex] { return track.cover }

        return [.gray, .gray]

    }

    // MARK: - 控制

    func play(index: Int? = nil) {

        if let index = index {

            // 点到当前正在播放的同一首：不重建 item，只切换播放/暂停，避免列表点歌从头播放。

            if index == currentIndex, player != nil {

                togglePlay()

                return

            }

            currentIndex = index

        }

        guard tracks.indices.contains(currentIndex) else { return }

        setupAndPlay(tracks[currentIndex])

    }

    /// 明确恢复播放（锁屏 playCommand / 音频中断恢复 / 睡眠取消用）。
    /// 关键：不在这里手动写 `isPlaying`，改由 timeControlStatus 的 sink 作为唯一真值来源，
    /// 否则快速连点时本地推断值与 AVPlayer 实际状态错位 → 出现「显示暂停实际在播放」。
    func resumePlayback() {
        guard let player = player else {
            play(index: currentIndex)
            return
        }
        // 正在缓冲(.waiting)或已暂停时调用 play() 都安全；已在播放则幂等。
        player.play()
        player.rate = playbackRate
    }

    /// 明确暂停（锁屏 pauseCommand / 睡眠到点 / 停止键用）。直接暂停，兼容缓冲中(.waiting)态。
    func pausePlayback() {
        player?.pause()
    }

    /// 切换播放/暂停（App 内按钮 / 耳机线控单键 / togglePlayPauseCommand）。
    /// 决策依据 AVPlayer 实时 `timeControlStatus`，而非本地推断的 `isPlaying`，避免竞态。
    func togglePlay() {
        guard let player = player else {
            play(index: currentIndex)
            return
        }
        if player.timeControlStatus == .playing {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    /// 循环切换播放模式：顺序 → 列表循环 → 单曲循环 → 随机

    func cyclePlaybackMode() {

        let order: [PlaybackMode] = [.order, .loop, .single, .shuffle]

        guard let i = order.firstIndex(of: playbackMode) else { playbackMode = .order; return }

        playbackMode = order[(i + 1) % order.count]

    }

    func next() {

        guard !tracks.isEmpty else { return }

        let i: Int

        switch playbackMode {

        case .order, .loop, .single:

            i = (currentIndex + 1) % tracks.count

        case .shuffle:

            i = Int.random(in: 0..<tracks.count)

        }

        play(index: i)

    }

    func previous() {

        guard !tracks.isEmpty else { return }

        let i = (currentIndex - 1 + tracks.count) % tracks.count

        play(index: i)

    }

    func seek(to second: Double) {

        guard let player = player else { return }

        let cm = CMTime(seconds: max(0, second), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        // 用小容差（0.1s）：zero tolerance 在 H.264/H.265 视频上常失败导致 item.status=failed
        // （之前「拖一下只播 2 秒就停」同源问题）。音频几乎无感。
        let tol = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cm, toleranceBefore: tol, toleranceAfter: tol) { _ in }

        currentTime = second

    }

    /// 设置睡眠定时：minutes=nil 取消，到点自动暂停。

    func setSleep(minutes: Int?) {

        sleepTimer?.invalidate()

        sleepTimer = nil

        if let m = minutes {

            sleepRemaining = m * 60

            sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in

                guard let self = self else { return }

                self.sleepRemaining -= 1

                if self.sleepRemaining <= 0 {

                    self.sleepTimer?.invalidate()

                    self.sleepTimer = nil

                    self.sleepRemaining = 0

                    self.player?.pause()

                    self.isPlaying = false

                    // 睡眠到点也保留锁屏卡片+控制（rate=0），不再清空

                    self.updateNowPlaying()

                }

            }

        } else {

            sleepRemaining = 0

        }

    }

    // MARK: - 播放器装配

    private func setupAndPlay(_ track: Track) {

        // 播放前确保 AudioSession 处于激活态（幂等）：息屏/来电中断/长时间运行后 session 可能被系统停用。
        // 注意：不能 setActive(false) 重置——App 在后台时 setActive(false) 会让锁屏/灵动岛控制失效且卡顿。
        try? AVAudioSession.sharedInstance().setActive(true)

        cleanupObservers()

        // 串音修复：销毁旧 player 前必须先显式 pause + 清空 item。
        // 之前只做 `player = nil` 靠 ARC 释放，但 AVPlayer 底层 audio queue 是 CF 对象、
        // 不会立即停止输出，新曲一响就与旧音频重叠（尤其 MP4 视频切换时最明显）。
        // pause() 会同步停止旧音频队列，replaceCurrentItem(with: nil) 进一步摘除解码源。
        if let oldPlayer = player {
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
        }
        // 必须先停掉旧 player，否则 applyEQToCurrentItem 会触发 replaceCurrentItem，

        // 在旧 tap 仍在渲染时迁移到新 item 容易导致 MTAudioProcessingTap 闪退。

        player = nil

        playerItem = nil

        currentTime = 0

        duration = 0

        title = track.title

        artist = track.artist

        album = track.album

        lyrics = track.lyrics

        lastLyricLine = ""

        // 覆盖：用户后期粘贴/导入的歌词（按曲目 id 持久化）优先于内嵌歌词

        if let custom = UserDefaults.standard.string(forKey: lyricsKey(for: track.id)), !custom.isEmpty {

            lyrics = custom

        }

        artwork = track.artwork

        if track.artwork == nil {
            Task { await self.fetchOnlineArtwork(title: track.title, artist: track.artist) }
        }

        isLoading = true

        lastError = nil

        isVideo = false

        let asset = AVURLAsset(url: track.url)

        let item = AVPlayerItem(asset: asset)

        // 检测是否为视频文件（MP4/MOV 等），供视频播放界面切换

        isVideo = !asset.tracks(withMediaType: .video).isEmpty

        playerItem = item

        // EQ 必须先在 AVPlayerItem 上挂好 audioMix，再交给 AVPlayer，否则 tap 可能永远不触发 prepare。

        applyEQToCurrentItem()

        player = AVPlayer(playerItem: item)

        player?.volume = volume

        player?.rate = playbackRate

        // 视频文件切后台/锁屏后继续播放音频（需要 UIBackgroundModes audio 已开启）。

        if #available(iOS 16.0, *) {

            player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible

        }

        // 进度观察（4fps 基础更新，足够 UI；高频场景可另行监听）
        // 播放时开启、暂停时移除（见 timeControlStatus sink），避免暂停后仍空转 CPU 导致发热。
        addTimeObserver()

        // 时长兜底：部分本地文件 item.duration 在 readyToPlay 时仍是 indefinite，

        // 这里额外监听 duration 一旦变有限值就修正，避免进度条总程只有 1 秒。

        item.publisher(for: \.duration)

            .receive(on: DispatchQueue.main)

            .sink { [weak self] d in

                let secs = CMTimeGetSeconds(d)

                if secs.isFinite, secs > 0 { self?.duration = secs }

            }

            .store(in: &cancellables)

        // 状态观察

        item.publisher(for: \.status)

            .receive(on: DispatchQueue.main)

            .sink { [weak self] st in

                guard let self = self else { return }

                switch st {

                case .readyToPlay:

                    let d = CMTimeGetSeconds(item.duration)

                    if d.isFinite, d > 0 { self.duration = d }

                    self.isLoading = false

                    self.sessionRetried = false

                    // EQ 已在 setupAndPlay 中提前挂接；这里不再重复 replace，避免播放中断。

                case .failed:

                    self.isLoading = false

                    self.lastError = item.error?.localizedDescription ?? "播放失败"

                    // 会话可能被系统停用导致本次加载失败：重新激活 session 并重试播放一次（防「全目录都不能播」）。
                    if !self.sessionRetried {
                        self.sessionRetried = true
                        try? AVAudioSession.sharedInstance().setActive(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            guard let self, self.player?.currentItem === item else { return }
                            self.player?.play()
                            self.player?.rate = self.playbackRate
                        }
                    }

                default:

                    break

                }

            }

            .store(in: &cancellables)

        // 同步系统播放状态：VideoPlayer / 切后台 / 锁屏 / 线控 导致的暂停，

        // 会及时反映到 isPlaying，避免播放/暂停按钮显示反了。

        player?.publisher(for: \.timeControlStatus)

            .receive(on: DispatchQueue.main)

            .sink { [weak self] status in

                guard let self = self else { return }

                self.isPlaying = (status == .playing)

                // 暂停（锁屏点暂停 / 中断 / 睡眠到点）时清空锁屏卡片 = 实现「后台关闭」；

                // 缓冲中(.waiting)保持卡片，避免刚点播放就闪退。

                if status == .paused {

                    // 暂停时停掉周期进度轮询：不空转 CPU（发热优化）

                    self.removeTimeObserverIfNeeded()

                    // 保留锁屏/灵动岛卡片 + 控制按钮可点：更新一次让 rate=0（系统用 rate 暂停且仍显示卡片）。
                    // 之前清空 nowPlayingInfo 导致锁屏「上一首/下一首/暂停」灰色不可用。

                    self.updateNowPlaying()

                    if #available(iOS 16.1, *) { self.updateLiveActivity() }

                } else {

                    self.addTimeObserver()

                    self.updateNowPlaying()

                    if #available(iOS 16.1, *) {
                        self.startLiveActivityIfNeeded()
                        self.updateLiveActivity()
                    }

                }

            }

            .store(in: &cancellables)

        // 播放结束 / 失败

        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: item)

        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFail), name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        player?.play()

        player?.rate = playbackRate

        isPlaying = true

        updateNowPlaying()

        if #available(iOS 16.1, *) {
            startLiveActivityIfNeeded()
            startLiveActivityTimer()
        }

        // 异步提取内嵌封面 / MP4 视频首帧，作为黑胶中心图

        if track.artwork == nil { loadArtwork(for: asset, track: track) }

        // 通知曲库记录「最近播放」

        NotificationCenter.default.post(name: .trackPlayed, object: nil, userInfo: ["id": track.id])

    }

    @objc private func playerDidFinish(_ notification: Notification) {

        switch playbackMode {

        case .order:

            if currentIndex + 1 < tracks.count {

                play(index: currentIndex + 1)

            } else {

                isPlaying = false

            }

        case .loop:

            play(index: (currentIndex + 1) % max(tracks.count, 1))

        case .single:

            seek(to: 0)

            player?.play()

            isPlaying = true

        case .shuffle:

            play(index: Int.random(in: 0..<max(tracks.count, 1)))

        }

    }

    @objc private func playerDidFail(_ notification: Notification) {

        isLoading = false

        if let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {

            lastError = err.localizedDescription

        }

    }

    // MARK: - 清理

    /// 周期进度观察（4fps）：播放时开启、暂停时移除（省 CPU 防发热）。
    private func addTimeObserver() {
        removeTimeObserverIfNeeded()
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self = self else { return }
            let s = CMTimeGetSeconds(t)
            if s.isFinite {
                // 拖动进度条期间不回写 currentTime，否则会和滑块的 set 互相覆盖、
                // 触发一连串零容差 seek 把 AVPlayer 搞到卡死（表现为「拖一下只播 2 秒就停」）。
                if !self.isScrubbing {
                    self.currentTime = s
                    // 歌词行变化时同步锁屏信息，使锁屏/控制中心显示当前行。
                    let line = self.currentLyricLine(at: s)
                    if line != self.lastLyricLine {
                        self.lastLyricLine = line
                        self.updateNowPlaying()
                    }
                }
                if s > self.duration { self.duration = s }
            }
        }
    }

    private func removeTimeObserverIfNeeded() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        timeObserver = nil
    }

    private func cleanupObservers() {

        removeTimeObserverIfNeeded()

        cancellables.removeAll()

        if let item = playerItem {

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)

            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        }

    }

    /// 完全停止播放并清空状态（当前曲目被移除等场景）。

    private func stopAndClear() {

        cleanupObservers()

        player?.pause()

        player = nil

        playerItem = nil

        processingTap = nil

        isPlaying = false

        isLoading = false

        currentTime = 0

        duration = 0

        title = "未在播放"

        artist = ""

        album = ""

        artwork = nil

        lyrics = nil

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
        if #available(iOS 16.1, *) { endLiveActivity() }
    }

    /// 异步提取内嵌封面（音频 artwork）或 MP4 视频首帧，赋值 engine.artwork。
    /// 兜底顺序：内嵌封面 → 同目录 cover.jpg/folder.jpg → MP4 首帧（限 800pt 防 OOM）。

    private func loadArtwork(for asset: AVAsset, track: Track) {

        Task { @MainActor [weak self] in

            guard let self = self else { return }

            // 1) 内嵌封面（常见音频格式 commonKey=artwork）

            if let item = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == "artwork" }),

               let data = item.value as? Data,

               let img = UIImage(data: data) {

                self.artwork = img

                return

            }

            // 2) 本地文件：同目录同名封面图兜底（cover.jpg / folder.jpg / 同名 jpg/png）

            if track.url.isFileURL, let img = Self.sidecarCover(for: track.url) {

                self.artwork = img

                return

            }

            // 3) MP4 / 视频文件：取首帧作为封面（maximumSize 限制，避免 4K 首帧 OOM）

            if !asset.tracks(withMediaType: .video).isEmpty {

                let gen = AVAssetImageGenerator(asset: asset)

                gen.appliesPreferredTrackTransform = true

                gen.maximumSize = CGSize(width: 800, height: 800)

                if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {

                    self.artwork = UIImage(cgImage: cg)

                }

            }

        }

    }

    /// 查找与音频同目录的同名封面图（cover.jpg / folder.jpg / 同名 .jpg/.png/.jpeg）。

    private static func sidecarCover(for url: URL) -> UIImage? {

        let dir = url.deletingLastPathComponent()

        let base = url.deletingPathExtension().lastPathComponent

        let fm = FileManager.default

        let candidates = [

            "cover.jpg", "cover.png", "cover.jpeg",

            "folder.jpg", "folder.png", "folder.jpeg",

            "\(base).jpg", "\(base).png", "\(base).jpeg"

        ]

        for name in candidates {

            let p = dir.appendingPathComponent(name)

            if fm.fileExists(atPath: p.path), let img = UIImage(contentsOfFile: p.path) {

                return img

            }

        }

        return nil

    }

    // MARK: - 灵动岛 / Live Activity（主 App 侧启动与更新；灵动岛 UI 由 Widget 扩展提供，见 JukeboxWidget.swift）

    /// 当前时间对应的歌词行（用于灵动岛展示），无歌词返回空串。
    private func currentLyricLine(at time: Double) -> String {
        guard let lrc = lyrics, !lrc.isEmpty else { return "" }
        var bestLine = ""
        var bestTime = -1.0
        for raw in lrc.split(separator: "\n") {
            var s = String(raw)
            guard let open = s.firstIndex(of: "["),
                  let close = s[s.index(after: open)...].firstIndex(of: "]") else { continue }
            let tag = s[s.index(after: open)..<close]
            let parts = tag.split(separator: ":")
            guard parts.count >= 2,
                  let m = Double(parts[0]),
                  let sec = Double(parts[1]) else { continue }
            let t = m * 60 + sec
            let text = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if t <= time, t > bestTime { bestTime = t; bestLine = text }
        }
        return bestLine
    }

    @available(iOS 16.1, *)
    private var jukeboxActivityState: JukeboxLiveActivityAttributes.ContentState {
        JukeboxLiveActivityAttributes.ContentState(
            isPlaying: isPlaying,
            elapsed: currentTime,
            duration: duration,
            currentLine: currentLyricLine(at: currentTime))
    }

    @available(iOS 16.1, *)
    private func startLiveActivityIfNeeded() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if liveActivityID != nil { updateLiveActivity(); return }
        let attrs = JukeboxLiveActivityAttributes(title: title, artist: artist)
        do {
            let activity = try Activity.request(attributes: attrs, contentState: jukeboxActivityState, pushType: nil)
            liveActivityID = activity.id
        } catch {
            #if DEBUG
            print("Live Activity 启动失败（缺 Widget 扩展或系统不支持）：\(error)")
            #endif
        }
    }

    @available(iOS 16.1, *)
    private func updateLiveActivity() {
        guard let id = liveActivityID,
              let activity = Activity<JukeboxLiveActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        Task { await activity.update(using: jukeboxActivityState) }
    }

    @available(iOS 16.1, *)
    private func endLiveActivity() {
        guard let id = liveActivityID,
              let activity = Activity<JukeboxLiveActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        Task { await activity.end(dismissalPolicy: .immediate) }
        liveActivityID = nil
    }

    @available(iOS 16.1, *)
    private func startLiveActivityTimer() {
        liveActivityTimer?.invalidate()
        liveActivityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateLiveActivity() }
        }
    }

    // MARK: - 锁屏信息

    private func updateNowPlaying() {

        var info: [String: Any] = [:]

        info[MPMediaItemPropertyTitle] = title

        info[MPMediaItemPropertyArtist] = artist.isEmpty ? nil : artist

        info[MPMediaItemPropertyAlbumTitle] = album.isEmpty ? nil : album

        info[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : nil

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let lyrics = lyrics, !lyrics.isEmpty {
            // 锁屏/控制中心优先显示当前歌词行；无时间轴时回退到纯文本。
            let line = currentLyricLine(at: currentTime)
            info[MPMediaItemPropertyLyrics] = line.isEmpty ? Self.plainLyrics(lyrics) : line
        }
        // 必须始终设 artwork：iOS 18 设计——锁屏卡片无封面图时所有控制（上一首/下一首/暂停）灰色不可点。
        // 无内嵌封面时用 currentCover 渐变合成占位图，让卡片完整 + 控制可用。
        let artImage = artwork ?? placeholderArtworkImage()
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: artImage)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    }

    /// 用 currentCover 颜色合成一张占位封面图（用于锁屏/控制中心当曲目无内嵌封面时）。
    /// 缓存：颜色未变复用旧图，避免每帧重绘。
    private func placeholderArtworkImage() -> UIImage {
        let key = currentCover.map { UIColor($0).description }.joined(separator: "|")
        if let cached = cachedPlaceholderArtwork, cachedPlaceholderKey == key {
            return cached
        }
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let cgColors = currentCover.map { UIColor($0).cgColor }
            if cgColors.count >= 2,
               let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: cgColors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(grad,
                                       start: CGPoint(x: 0, y: size.height),
                                       end: CGPoint(x: size.width, y: 0),
                                       options: [])
            } else {
                UIColor(white: 0.15, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
        }
        cachedPlaceholderArtwork = img
        cachedPlaceholderKey = key
        return img
    }

    /// 把带时间轴的 LRC 转成纯文本（去掉 [mm:ss.xx] 行首时间戳），用于锁屏歌词显示（锁屏不支持逐行高亮）。
    private static func plainLyrics(_ lrc: String) -> String {
        lrc.split(separator: "\n").map { line in
            var s = line
            while let open = s.firstIndex(of: "["), let close = s[s.index(after: open)...].firstIndex(of: "]") {
                s.removeSubrange(open...close)
            }
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 内嵌封面为空时，异步拉取在线专辑图（iTunes Search API，免费无需密钥）兜底，解决「部分歌曲识别不到头像」。
    private func fetchOnlineArtwork(title: String, artist: String) async {
        let term = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(term)&entity=song&limit=1") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let artUrlStr = first["artworkUrl100"] as? String,
              let artUrl = URL(string: artUrlStr.replacingOccurrences(of: "100x100", with: "300x300")) else { return }
        guard let (imgData, _) = try? await URLSession.shared.data(from: artUrl),
              let img = UIImage(data: imgData) else { return }
        self.artwork = img
        updateNowPlaying()
    }

    // MARK: - 音频会话

    private func setupAudioSession() {

        do {

            // 显式允许蓝牙（A2DP 耳机/音箱）路由，否则部分设备连上蓝牙仍走扬声器

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,

                options: [.allowBluetooth, .allowBluetoothA2DP])

            try AVAudioSession.sharedInstance().setActive(true)

        } catch {

            #if DEBUG

            print("音频会话设置失败: \(error)")

            #endif

        }

    }

    // MARK: - 远程控制（锁屏 / 控制中心）

    private func setupRemoteCommands() {

        let center = MPRemoteCommandCenter.shared()

        // 显式启用所有锁屏/控制中心命令，避免 iOS 因缺少命令状态而置灰。
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        // 关键：必须显式禁用 skipForward/skipBackward（不注册 handler）。
        // iOS 17+ 只要检测到 skip 命令，锁屏布局就会用「-15s/+15s」按钮替换「上一首/下一首」，
        // 用户要求的是老版本布局（直接上一首/下一首切换）。
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.skipForwardCommand.removeTarget(self)
        center.skipBackwardCommand.removeTarget(self)

        // 锁屏「播放」按钮：明确恢复，绝不能走 toggle（否则快速连点会与 pause 互相抵消）。
        center.playCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.resumePlayback() }

            return .success

        }

        // 锁屏「暂停」按钮：明确暂停，不再走 toggle。
        center.pauseCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.pausePlayback() }

            return .success

        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.togglePlay() }

            return .success

        }

        center.nextTrackCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.next() }

            return .success

        }

        center.previousTrackCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.previous() }

            return .success

        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in

            if let evt = event as? MPChangePlaybackPositionCommandEvent {

                Task { @MainActor in self?.seek(to: evt.positionTime) }

                return .success

            }

            return .commandFailed

        }

        // 「停止」指令：耳机线控 / CarPlay / 系统媒体键的停止键触发时，

        // 暂停并清空锁屏卡片（即「后台关闭」）。

        // 「停止」指令：耳机线控 / CarPlay / 系统媒体键 → 暂停并清空锁屏卡片。
        // 直接暂停（不依赖 isPlaying 判断），由 sink 在 status==.paused 时清卡片。
        center.stopCommand.addTarget { [weak self] _ in

            Task { @MainActor in self?.pausePlayback() }

            return .success

        }

    }

    // MARK: - 通知监听

    private func setupNotifications() {

        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)

    }

    @objc private func handleInterruption(_ notification: Notification) {

        guard let info = notification.userInfo,

              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,

              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {

        case .began:

            player?.pause(); isPlaying = false

        case .ended:

            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,

               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {

                // 中断结束后必须重新激活 session 再恢复播放，否则所有曲目会静默失败（息屏/来电后全目录不能播的根因之一）。
                try? AVAudioSession.sharedInstance().setActive(true)

                player?.play(); isPlaying = true

                player?.rate = playbackRate

            }

        @unknown default:

            break

        }

    }

    @objc private func handleRouteChange(_ notification: Notification) {

        guard let info = notification.userInfo,

              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,

              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // 仅当「已无任何输出设备」时才暂停（真正的断开，如拔掉耳机且无其他输出）。

        // 连上蓝牙时旧设备会变为 unavailable，但新路由（蓝牙）已生效，应继续播放，不应误暂停。

        if reason == .oldDeviceUnavailable {

            let hasOutput = !AVAudioSession.sharedInstance().currentRoute.outputs.isEmpty

            if !hasOutput {

                player?.pause(); isPlaying = false

            }

        }

    }

    // MARK: - 歌词（粘贴 / 导入 / 内置示例，按曲目持久化）

    private func lyricsKey(for id: UUID) -> String { "JukeboxLyrics_\(id.uuidString)" }

    /// 设置当前播放曲目的歌词（粘贴或导入 LRC/纯文本），按曲目 id 持久化到 UserDefaults。

    /// 空字符串表示清除。

    func setLyricsForCurrent(_ text: String) {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        lyrics = trimmed.isEmpty ? nil : trimmed

        if let id = tracks[safe: currentIndex]?.id {

            if trimmed.isEmpty {

                UserDefaults.standard.removeObject(forKey: lyricsKey(for: id))

            } else {

                UserDefaults.standard.set(trimmed, forKey: lyricsKey(for: id))

            }

        }

    }

    /// 内置示例 LRC，用于没有歌词的歌曲验证「歌词偏移」功能。

    func loadSampleLyricsForCurrent() {

        let sample = """

        [00:00.00]Jukebox 示例歌词

        [00:04.00]这是一段内置的 LRC

        [00:08.00]用来测试歌词偏移 ±0.5s

        [00:12.00]点击 +/- 调整时间轴

        [00:16.00]看歌词是否同步滚动

        [00:20.00]music ♪ ~ ♪

        [00:24.00]如果偏了就再微调

        [00:28.00]直到对上演唱的节奏

        [00:32.00]Enjoy your music

        """

        setLyricsForCurrent(sample)

    }

    // MARK: - EQ 音效（MTAudioProcessingTap，默认关闭）

    /// 根据开关/预设，给当前 playerItem 挂上或卸下 EQ 音频混合。

    /// 关键点：

    /// - 必须先把 audioMix 挂到 AVPlayerItem，再交给 AVPlayer，否则 tap 的 prepare 可能永远不触发。

    /// - 如果 player 已经在播，需要 replaceCurrentItem 才能让新的 audioMix 生效。

    /// - AVMutableAudioMixInputParameters 必须绑定到 asset 的真实音轨 trackID，默认 trackID=0 不会生效。

    /// - 注意：本方法只在「开关切换 / 切歌 / 音轨首次就绪」时被调用（会 replaceCurrentItem）。

    ///   单纯调整增益（拖动滑块）走 updateEQBandsOnly，不 replace，避免播放卡死。

    private func applyEQToCurrentItem() {

        guard let item = playerItem else { return }

        guard eqEnabled else {

            item.audioMix = nil

            processingTap = nil

            replaceCurrentItemIfNeeded()

            refreshEQDiagnostic()

            return

        }

        // 开启但增益全 0（理论上 selectPreset 已填，这里是兜底）：自动补一个预设，避免「开了却没变化」。

        var bands = eqBands

        if bands.allSatisfy({ $0 == 0 }) {

            let filled = EQAudioTap.presets[eqPreset] ?? EQAudioTap.presets["低音"] ?? Array(repeating: 0, count: EQAudioTap.bandCount)

            bands = filled

            // 同步到 UI：异步设置，避免在本函数内触发 eqBands.didSet -> updateEQBandsOnly -> applyEQToCurrentItem 递归。

            DispatchQueue.main.async { [weak self] in self?.eqBands = filled }

        }

        eqTap.setBands(bands)

        guard let tap = createEQTap() else {

            item.audioMix = nil

            processingTap = nil

            replaceCurrentItemIfNeeded()

            refreshEQDiagnostic()

            return

        }

        processingTap = tap

        // 本地文件通常能同步取到音轨；远程/未加载完成的 fallback 到异步加载后再试一次。

        let audioTracks = item.asset.tracks(withMediaType: .audio)

        if audioTracks.isEmpty {

            eqDiagnostic = "⏳ 正在等待音轨加载…"

            Task { @MainActor [weak self] in

                guard let self = self, self.playerItem === item else { return }

                do {

                    let tracks = try await item.asset.loadTracks(withMediaType: .audio)

                    guard !tracks.isEmpty else {

                        self.eqDiagnostic = "⚠️ 该曲目无音频轨，EQ 无法挂接"

                        return

                    }

                    self.applyEQToCurrentItem()

                } catch {

                    self.eqDiagnostic = "⚠️ 加载音轨失败：\(error.localizedDescription)"

                }

            }

            return

        }

        var params: [AVAudioMixInputParameters] = []

        for track in audioTracks {

            // 用 init(track:) 而非默认 init + 手动 trackID，

            // 确保 inputParameters 与 asset 音轨正确关联，tap 才能被触发。

            let p = AVMutableAudioMixInputParameters(track: track)

            p.audioTapProcessor = tap

            params.append(p)

        }

        let mix = AVMutableAudioMix()

        mix.inputParameters = params

        item.audioMix = mix

        replaceCurrentItemIfNeeded()

        refreshEQDiagnostic()

    }

    /// 当 player 已在播放时，audioMix 变化需要 replaceCurrentItem 才会被重新采纳。

    private func replaceCurrentItemIfNeeded() {

        guard let player = player, let item = playerItem else { return }

        let wasPlaying = isPlaying

        let ct = currentTime

        player.replaceCurrentItem(with: nil)

        player.replaceCurrentItem(with: item)

        if ct > 0 {

            player.seek(to: CMTime(seconds: ct, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }

        }

        if wasPlaying {

            player.play()

            player.rate = playbackRate   // 关键：replaceCurrentItem 会重置 rate，必须恢复用户设定的速度

            isPlaying = true

        }

    }

    /// 拖动 10 段滑块时只把新增益喂给已存在的 tap，**不重建 audioMix、不 replaceCurrentItem**。

    /// MTAudioProcessingTap 的设计允许直接在渲染线程用新系数（内部有锁），无需重新挂接。

    /// 仅当 EQ 已开启但当前 item 还没挂上 tap（首次开启 / 切歌后）时才补一次完整挂接。

    private func updateEQBandsOnly() {

        eqTap.setBands(eqBands)

        if eqEnabled, playerItem?.audioMix == nil {

            applyEQToCurrentItem()

        }

    }

    /// 读取 EQ 处理状态，生成给人看的诊断文字。不要在音频渲染线程里调用。

    func refreshEQDiagnostic() {

        let s = eqTap.snapshot()

        let mixAttached = playerItem?.audioMix != nil

        let trackCount = playerItem?.asset.tracks(withMediaType: .audio).count ?? 0

        if !eqEnabled {

            eqDiagnostic = "均衡器已关闭"

        } else if s.frames > 0 {

            eqDiagnostic = "✅ EQ 已生效 · 已处理 \(s.frames) 帧 · \(s.format)"

        } else if mixAttached {

            eqDiagnostic = "⏳ EQ 已挂接(\(trackCount)轨)，等待音频数据 · \(s.format)"

        } else {

            eqDiagnostic = "⚠️ EQ 未挂接（无 audioMix / \(trackCount)轨）· \(s.format)"

        }

    }

    /// 创建 MTAudioProcessingTap 并绑定到 eqTap。eqTap 由 PlayerEngine 强引用，存储指针用 passUnretained，finalize 不释放。

    private func createEQTap() -> MTAudioProcessingTap? {

        let eq = self.eqTap

        var callbacks = MTAudioProcessingTapCallbacks(

            version: kMTAudioProcessingTapCallbacksVersion_0,

            clientInfo: Unmanaged.passUnretained(eq).toOpaque(),

            init: { (tap, clientInfo, tapStorageOut) in

                tapStorageOut.pointee = clientInfo

            },

            finalize: { _ in },

            prepare: { (tap, maxFrames, processingFormat) in

                let processor = Unmanaged<EQAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()

                let asbd = processingFormat.pointee

                processor.configure(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame), formatFlags: asbd.mFormatFlags)

            },

            unprepare: { _ in },

            process: { (tap, numberFrames, flags, bufferList, numberFramesOut, flagsOut) in

                let processor = Unmanaged<EQAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()

                var frames = numberFrames

                var f = flags

                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, &f, nil, &frames)

                numberFramesOut.pointee = frames

                flagsOut.pointee = f

                if status == noErr {

                    processor.process(bufferList: bufferList, numberFrames: Int(frames))

                }

            }

        )

        var tap: MTAudioProcessingTap?

        // 用 PreEffects 标志创建 tap，确保在系统其他效果处理之前拿到解码后 PCM。

        // 实测传 0 在某些 iOS/重签名环境下会导致 prepare/process 不被调用。

        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)

        if status == noErr { return tap }

        return nil

    }

}

// MARK: - Helpers

extension Collection {

    subscript(safe index: Index) -> Element? {

        indices.contains(index) ? self[index] : nil

    }

}

// MARK: - EQ 处理核心（10 段 Graphic EQ，全 Peaking）

/// 10 段图形均衡器：31/62/125/250/500/1k/2k/4k/8k/16k，每段 Peaking（Q≈1.0，听感顺滑）。

/// 通过 MTAudioProcessingTap 接入 AVPlayer，渲染线程与主线程共享状态，已加 NSLock 保护。

final class EQAudioTap: @unchecked Sendable {

    /// 频段数（presets 数组长度必须一致）

    static let bandCount = 10

    /// 各频段中心频率（Hz）

    static let freqs: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// 频段标签（UI 显示用）

    static let freqLabels: [String] = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    /// 预设名 -> 10 个频段增益（dB，顺序对应 freqs）。差异刻意拉满、互不重叠，方便听感对比。

    /// 增加「默认」全 0 平直曲线，作为首次开启 EQ 的安全起点。

    static let presets: [String: [Double]] = [

        "默认":   [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],

        "重低音": [12, 10, 6, 2, 0, 0, 0, 0, 0, 0],

        "低音":   [8, 6, 3, 1, 0, 0, 0, 0, 0, 0],

        "人声":   [0, 0, 0, 2, 4, 6, 6, 3, 0, 0],

        "明亮":   [0, 0, 0, 0, 0, 0, 2, 5, 8, 10],

        "流行":   [5, 4, 0, -2, -3, 0, 2, 3, 5, 6],

        "古典":   [4, 3, 2, 0, -2, -2, 0, 2, 4, 5],

        "摇滚":   [6, 5, 3, 1, 0, 0, 2, 3, 5, 6],

    ]

    private struct Coeffs { var b0: Float = 0; var b1: Float = 0; var b2: Float = 0; var a1: Float = 0; var a2: Float = 0 }

    private let lock = NSLock()

    private var filters: [[Coeffs]] = []   // [band][channel]

    private var z1: [[Float]] = []         // [channel][band]

    private var z2: [[Float]] = []         // [channel][band]

    private var bands: [Double] = Array(repeating: 0, count: EQAudioTap.bandCount)

    private var sampleRate: Double = 44100

    private var channels: Int = 2

    private var isFloat: Bool = false

    private var isNonInterleaved: Bool = true

    private var valid: Bool = false

    private var formatDesc: String = "未初始化"

    private var processedFrames: Int64 = 0

    func setBands(_ newBands: [Double]) {

        lock.lock()

        var b = newBands

        if b.count < EQAudioTap.bandCount { b.append(contentsOf: Array(repeating: 0, count: EQAudioTap.bandCount - b.count)) }

        if b.count > EQAudioTap.bandCount { b = Array(b.prefix(EQAudioTap.bandCount)) }

        bands = b

        recompute()

        lock.unlock()

    }

    func configure(sampleRate: Double, channels: Int, formatFlags: UInt32) {

        lock.lock()

        self.sampleRate = sampleRate

        self.channels = max(1, channels)

        // kAudioFormatFlagIsFloat        = 1 << 0

        // kAudioFormatFlagIsNonInterleaved = 1 << 5

        self.isFloat = (formatFlags & (1 << 0)) != 0

        self.isNonInterleaved = (formatFlags & (1 << 5)) != 0

        // 只要浮点就处理（非交错/交错都能处理）；非浮点格式跳过，避免读错内存。

        self.valid = self.isFloat

        self.formatDesc = "\(self.isFloat ? "浮点" : "整型")\(self.isNonInterleaved ? "非交错" : "交错") \(self.channels)ch / \(Int(self.sampleRate))Hz"

        recompute()

        lock.unlock()

    }

    private func recompute() {

        let q: Double = 1.0

        var newFilters: [[Coeffs]] = []

        for band in 0..<EQAudioTap.bandCount {

            var chFilters: [Coeffs] = []

            let g = bands.count > band ? bands[band] : 0

            let f = EQAudioTap.freqs[band]

            for _ in 0..<channels {

                chFilters.append(peaking(sampleRate: sampleRate, freq: f, gainDB: g, q: q))

            }

            newFilters.append(chFilters)

        }

        filters = newFilters

        z1 = Array(repeating: Array(repeating: 0, count: EQAudioTap.bandCount), count: channels)

        z2 = Array(repeating: Array(repeating: 0, count: EQAudioTap.bandCount), count: channels)

    }

    // MARK: - RBJ 系数（Peaking，全频段统一用）

    private func peaking(sampleRate: Double, freq: Double, gainDB: Double, q: Double) -> Coeffs {

        let A = pow(10, gainDB / 40)

        let w0 = 2 * .pi * freq / sampleRate

        let cosw0 = cos(w0)

        let alpha = sin(w0) / (2 * q)

        let a0 = 1 + alpha / A

        return Coeffs(

            b0: Float((1 + alpha * A) / a0),

            b1: Float((-2 * cosw0) / a0),

            b2: Float((1 - alpha * A) / a0),

            a1: Float((-2 * cosw0) / a0),

            a2: Float((1 - alpha / A) / a0)

        )

    }

    /// 对 AudioBufferList 做 in-place 处理。非 Float32 或格式不支持时直接跳过，避免读错内存。

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, numberFrames: Int) {

        guard numberFrames > 0 else { return }

        lock.lock()

        defer { lock.unlock() }

        guard valid else { return }

        processedFrames += Int64(numberFrames)

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)

        if isNonInterleaved {

            let nch = min(channels, abl.count)

            for ch in 0..<nch {

                guard let data = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }

                for band in 0..<EQAudioTap.bandCount {

                    let c = filters[band][ch]

                    var z1v = z1[ch][band]

                    var z2v = z2[ch][band]

                    for i in 0..<numberFrames {

                        let x = data[i]

                        let y = c.b0 * x + z1v

                        z1v = c.b1 * x - c.a1 * y + z2v

                        z2v = c.b2 * x - c.a2 * y

                        // NaN/Inf 保护：状态异常时重置滤波器，避免异常值扩散导致音频引擎闪退。

                        guard y.isFinite, z1v.isFinite, z2v.isFinite else {

                            z1v = 0; z2v = 0; data[i] = 0; continue

                        }

                        // 限制输出幅度在合理范围，防止极端增益导致系统音频渲染异常。

                        data[i] = max(-4.0, min(4.0, y))

                    }

                    z1[ch][band] = z1v

                    z2[ch][band] = z2v

                }

            }

        } else {

            // Interleaved：所有通道交错存放在一个 buffer 里（单声道时与 non-interleaved 等价）

            guard let data = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }

            let nch = channels

            for frame in 0..<numberFrames {

                for ch in 0..<nch {

                    let idx = frame * nch + ch

                    var y = data[idx]

                    for band in 0..<EQAudioTap.bandCount {

                        let c = filters[band][ch]

                        var z1v = z1[ch][band]

                        var z2v = z2[ch][band]

                        let x = y

                        y = c.b0 * x + z1v

                        z1v = c.b1 * x - c.a1 * y + z2v

                        z2v = c.b2 * x - c.a2 * y

                        // NaN/Inf 保护与幅度限制，防止异常样本导致闪退。

                        guard y.isFinite, z1v.isFinite, z2v.isFinite else {

                            z1v = 0; z2v = 0; y = 0; continue

                        }

                        y = max(-4.0, min(4.0, y))

                        z1[ch][band] = z1v

                        z2[ch][band] = z2v

                    }

                    data[idx] = y

                }

            }

        }

    }

    /// 供播放页诊断用：返回当前处理格式、已处理帧数、是否生效。

    func snapshot() -> (format: String, frames: Int64, valid: Bool, active: Bool) {

        lock.lock(); defer { lock.unlock() }

        return (formatDesc, processedFrames, valid, processedFrames > 0)

    }

}

// MARK: - 通知

extension Notification.Name {

    /// 曲目开始播放时发送（userInfo["id"] = Track.ID），供曲库记录「最近播放」。

    static let trackPlayed = Notification.Name("JukeboxTrackPlayed")

}

