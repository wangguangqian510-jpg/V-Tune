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

    // MARK: - EQ 音效（默认关闭，避免影响基础播放稳定性）
    @Published var eqEnabled: Bool = false {
        didSet {
            // 开启时若还是「关闭」占位预设，自动切到有听感差异的预设，避免「开了却没变化」。
            if eqEnabled && !EQAudioTap.presets.keys.contains(eqPreset) {
                eqPreset = "低音增强"
            }
            applyEQToCurrentItem()
        }
    }
    @Published var eqPreset: String = "低音增强" {
        didSet { applyEQToCurrentItem() }
    }
    /// EQ 诊断文字（播放页展示用，确认 tap 是否真的在处理音频）
    @Published var eqDiagnostic: String = "均衡器已关闭"
    private let eqTap = EQAudioTap()
    private var processingTap: MTAudioProcessingTap?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupAudioSession()
        setupRemoteCommands()
        setupNotifications()
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

    // MARK: - 播放器装配

    private func setupAndPlay(_ track: Track) {
        cleanupObservers()

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
        isPlaying = true
        updateNowPlaying()
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

        guard eqEnabled, let bands = EQAudioTap.presets[eqPreset] else {
            item.audioMix = nil
            processingTap = nil
            replaceCurrentItemIfNeeded()
            refreshEQDiagnostic()
            return
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
            Task { @MainActor [weak self] in
                guard let self = self, self.playerItem === item else { return }
                do {
                    let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else { return }
                    self.applyEQToCurrentItem()
                } catch {
                    #if DEBUG
                    print("EQ 异步加载音轨失败: \(error)")
                    #endif
                }
            }
            return
        }

        var params: [AVAudioMixInputParameters] = []
        for track in audioTracks {
            let p = AVMutableAudioMixInputParameters()
            p.trackID = track.trackID
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
        if !eqEnabled {
            eqDiagnostic = "均衡器已关闭"
        } else if s.frames > 0 {
            eqDiagnostic = "✅ EQ 已生效 · 已处理 \(s.frames) 帧 · \(s.format)"
        } else if let item = playerItem, item.audioMix != nil {
            eqDiagnostic = "⏳ EQ 已挂接，等待音频数据 · \(s.format)"
        } else {
            eqDiagnostic = "⚠️ EQ 未挂接（格式/曲目不支持）· \(s.format)"
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
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, 0, &tap)
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

// MARK: - EQ 处理核心（LowShelf / Peaking / HighShelf 组合）

/// 3 段 Biquad EQ：低频 LowShelf @100Hz、中频 Peaking @1kHz、高频 HighShelf @8kHz。
/// 通过 MTAudioProcessingTap 接入 AVPlayer，渲染线程与主线程共享状态，已加 NSLock 保护。
final class EQAudioTap: @unchecked Sendable {
    /// 预设名 -> [低频增益, 中频增益, 高频增益]（单位 dB）
    static let presets: [String: [Double]] = [
        "低音增强": [10, 0, 0],
        "人声":     [0, 6, 2],
        "明亮":     [0, 0, 8],
        "摇滚":     [6, 2, 5],
    ]

    private enum BandType { case lowShelf, peaking, highShelf }
    private struct Coeffs { var b0: Float = 0; var b1: Float = 0; var b2: Float = 0; var a1: Float = 0; var a2: Float = 0 }

    private let lock = NSLock()
    private var filters: [[Coeffs]] = []   // [band][channel]
    private var z1: [[Float]] = []         // [channel][band]
    private var z2: [[Float]] = []         // [channel][band]
    private var bands: [Double] = [0, 0, 0]
    private var sampleRate: Double = 44100
    private var channels: Int = 2
    private var isFloat: Bool = false
    private var isNonInterleaved: Bool = true
    private var valid: Bool = false
    private var formatDesc: String = "未初始化"
    private var processedFrames: Int64 = 0

    func setBands(_ newBands: [Double]) {
        lock.lock()
        bands = newBands
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
        let freqs = [100.0, 1000.0, 8000.0]
        let qs = [0.7, 1.0, 0.7]
        let types: [BandType] = [.lowShelf, .peaking, .highShelf]

        var newFilters: [[Coeffs]] = []
        for band in 0..<3 {
            var chFilters: [Coeffs] = []
            let g = bands.count > band ? bands[band] : 0
            for _ in 0..<channels {
                let c: Coeffs
                switch types[band] {
                case .lowShelf:  c = lowShelf(sampleRate: sampleRate, freq: freqs[band], gainDB: g, q: qs[band])
                case .peaking:   c = peaking(sampleRate: sampleRate, freq: freqs[band], gainDB: g, q: qs[band])
                case .highShelf: c = highShelf(sampleRate: sampleRate, freq: freqs[band], gainDB: g, q: qs[band])
                }
                chFilters.append(c)
            }
            newFilters.append(chFilters)
        }
        filters = newFilters
        z1 = Array(repeating: Array(repeating: 0, count: 3), count: channels)
        z2 = Array(repeating: Array(repeating: 0, count: 3), count: channels)
    }

    // MARK: - RBJ 系数

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

    private func lowShelf(sampleRate: Double, freq: Double, gainDB: Double, q: Double) -> Coeffs {
        let A = sqrt(pow(10, gainDB / 20))
        let w0 = 2 * .pi * freq / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / 2 * sqrt((A + 1/A) * (1/q - 1) + 2)
        let sqrtA2 = 2 * sqrt(A) * alpha
        let a0 = (A + 1) + (A - 1) * cosw0 + sqrtA2
        return Coeffs(
            b0: Float((A * ((A + 1) - (A - 1) * cosw0 + sqrtA2)) / a0),
            b1: Float((2 * A * ((A - 1) - (A + 1) * cosw0)) / a0),
            b2: Float((A * ((A + 1) - (A - 1) * cosw0 - sqrtA2)) / a0),
            a1: Float((-2 * ((A - 1) + (A + 1) * cosw0)) / a0),
            a2: Float(((A + 1) + (A - 1) * cosw0 - sqrtA2) / a0)
        )
    }

    private func highShelf(sampleRate: Double, freq: Double, gainDB: Double, q: Double) -> Coeffs {
        let A = sqrt(pow(10, gainDB / 20))
        let w0 = 2 * .pi * freq / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / 2 * sqrt((A + 1/A) * (1/q - 1) + 2)
        let sqrtA2 = 2 * sqrt(A) * alpha
        let a0 = (A + 1) - (A - 1) * cosw0 + sqrtA2
        return Coeffs(
            b0: Float((A * ((A + 1) + (A - 1) * cosw0 + sqrtA2)) / a0),
            b1: Float((-2 * A * ((A - 1) + (A + 1) * cosw0)) / a0),
            b2: Float((A * ((A + 1) + (A - 1) * cosw0 - sqrtA2)) / a0),
            a1: Float((2 * ((A - 1) - (A + 1) * cosw0)) / a0),
            a2: Float(((A + 1) - (A - 1) * cosw0 - sqrtA2) / a0)
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
                for band in 0..<3 {
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
                    for band in 0..<3 {
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
