import Foundation
import Combine
import UIKit
import SwiftUI
import MediaPlayer
import AVFoundation
import AudioToolbox

/// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机
enum PlaybackMode: String, CaseIterable {
    case order
    case loop
    case single
    case shuffle
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
    @Published private(set) var duration: Double = 0
    @Published private(set) var title: String = "未在播放"
    @Published private(set) var artist: String = ""
    @Published private(set) var album: String = ""
    @Published private(set) var artwork: UIImage?
    @Published private(set) var lyrics: String?
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
            // 开启时若还没任何增益（全 0），自动填一个有明显听感的预设，避免「开了却没变化」。
            if eqEnabled, eqBands.allSatisfy({ $0 == 0 }) {
                selectPreset("低音")
            } else {
                applyEQToCurrentItem()
            }
        }
    }
    /// 当前生效的 10 段增益（dB），由预设填充或被图形化滑块修改。
    @Published var eqBands: [Double] = Array(repeating: 0, count: EQAudioTap.bandCount) {
        didSet {
            UserDefaults.standard.set(eqBands, forKey: eqBandsKey)
            applyEQToCurrentItem()
        }
    }
    /// UI 选中的预设名（仅用于展示；选预设会填充 eqBands）。
    @Published var eqPreset: String = "低音" {
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
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

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
        if let saved = UserDefaults.standard.string(forKey: eqPresetKey) {
            eqPreset = saved
        }
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
        if let index = index { currentIndex = index }
        guard tracks.indices.contains(currentIndex) else { return }
        setupAndPlay(tracks[currentIndex])
    }

    func togglePlay() {
        guard let player = player else {
            play(index: currentIndex)
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
        updateNowPlaying()
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
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
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
                    self.updateNowPlaying()
                }
            }
        } else {
            sleepRemaining = 0
        }
    }

    // MARK: - 播放器装配

    private func setupAndPlay(_ track: Track) {
        cleanupObservers()
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
        artwork = nil
        isLoading = true
        lastError = nil

        let asset = AVURLAsset(url: track.url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item
        // EQ 必须先在 AVPlayerItem 上挂好 audioMix，再交给 AVPlayer，否则 tap 可能永远不触发 prepare。
        applyEQToCurrentItem()
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        player?.rate = playbackRate

        // 进度观察（4fps 基础更新，足够 UI；高频场景可另行监听）
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self = self else { return }
            let s = CMTimeGetSeconds(t)
            if s.isFinite {
                // 拖动进度条期间不回写 currentTime，否则会和滑块的 set 互相覆盖、
                // 触发一连串零容差 seek 把 AVPlayer 搞到卡死（表现为「拖一下只播 2 秒就停」）。
                if !self.isScrubbing { self.currentTime = s }
                if s > self.duration { self.duration = s }
            }
        }

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
                    // EQ 已在 setupAndPlay 中提前挂接；这里不再重复 replace，避免播放中断。
                case .failed:
                    self.isLoading = false
                    self.lastError = item.error?.localizedDescription ?? "播放失败"
                default:
                    break
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
        // 异步提取内嵌封面 / MP4 视频首帧，作为黑胶中心图
        loadArtwork(for: asset)
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

    private func cleanupObservers() {
        if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }
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
        updateNowPlaying()
    }

    /// 异步提取内嵌封面（音频 artwork）或 MP4 视频首帧，赋值 engine.artwork。
    private func loadArtwork(for asset: AVAsset) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // 1) 内嵌封面（常见音频格式 commonKey=artwork）
            if let item = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == "artwork" }),
               let data = item.value as? Data,
               let img = UIImage(data: data) {
                self.artwork = img
                return
            }
            // 2) MP4 / 视频文件：取首帧作为封面
            if !asset.tracks(withMediaType: .video).isEmpty {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                    self.artwork = UIImage(cgImage: cg)
                }
            }
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
            info[MPMediaItemPropertyLyrics] = lyrics
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
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
                player?.play(); isPlaying = true
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

    // MARK: - EQ 音效（MTAudioProcessingTap，默认关闭）

    /// 根据开关/预设，给当前 playerItem 挂上或卸下 EQ 音频混合。
    /// 关键点：
    /// - 必须先把 audioMix 挂到 AVPlayerItem，再交给 AVPlayer，否则 tap 的 prepare 可能永远不触发。
    /// - 如果 player 已经在播，需要 replaceCurrentItem 才能让新的 audioMix 生效。
    /// - AVMutableAudioMixInputParameters 必须绑定到 asset 的真实音轨 trackID，默认 trackID=0 不会生效。
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
            bands = EQAudioTap.presets[eqPreset] ?? EQAudioTap.presets["低音"] ?? Array(repeating: 0, count: EQAudioTap.bandCount)
            eqBands = bands
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
            isPlaying = true
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
    static let presets: [String: [Double]] = [
        "重低音": [18, 18, 15, 10, 0, 0, 0, 0, 0, 0],
        "低音":   [12, 10, 6, 2, 0, 0, 0, 0, 0, 0],
        "人声":   [0, 0, 0, 0, 5, 9, 9, 5, 0, 0],
        "明亮":   [0, 0, 0, 0, 0, 0, 0, 4, 8, 12],
        "流行":   [8, 6, 0, -3, -4, 0, 2, 4, 6, 9],
        "古典":   [6, 4, 2, 0, -3, -3, 0, 3, 5, 7],
        "摇滚":   [9, 7, 4, 1, -1, -1, 2, 4, 6, 7],
        "测试":   [-30, -30, -30, -30, -30, -30, -30, -30, -30, -30],
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
                        data[i] = y
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
