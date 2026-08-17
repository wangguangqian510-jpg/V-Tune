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
        didSet { applyEQToCurrentItem() }
    }
    @Published var eqPreset: String = "关闭" {
        didSet { applyEQToCurrentItem() }
    }
    private let eqTap = EQAudioTap()
    private var processingTap: Unmanaged<MTAudioProcessingTap>?

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
        player = AVPlayer(playerItem: item)
        player?.volume = volume
        applyEQToCurrentItem()

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

    /// 根据开关/预设，给当前 playerItem 挂上或卸下 EQ 音频混合。eqEnabled 关闭时直接卸下。
    private func applyEQToCurrentItem() {
        guard let item = playerItem else { return }
        guard eqEnabled, let bands = EQAudioTap.presets[eqPreset] else {
            item.audioMix = nil
            return
        }
        eqTap.setBands(bands)
        guard let tap = createEQTap() else {
            item.audioMix = nil
            return
        }
        let params = AVMutableAudioMixInputParameters()
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    /// 创建 MTAudioProcessingTap 并绑定到 eqTap。eqTap 由 PlayerEngine 强引用，存储指针用 passUnretained，finalize 不释放。
    private func createEQTap() -> MTAudioProcessingTap? {
        let eq = self.eqTap
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { (tap, clientInfo, tapStorageOut) in
                tapStorageOut.pointee = UnsafeMutableRawPointer(Unmanaged.passUnretained(eq).toOpaque())
            },
            finalize: { _ in },
            prepare: { (tap, maxFrames, processingFormat) in
                let processor = Unmanaged<EQAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let asbd = processingFormat.pointee
                processor.configure(sampleRate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame))
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

// MARK: - EQ 处理核心（3 段 Biquad 峰值滤波）

/// 3 段 Biquad 峰值 EQ（低 80Hz / 中 1kHz / 高 10kHz），通过 MTAudioProcessingTap 接入 AVPlayer。
/// 处理在音频渲染线程进行；主线程切换预设时仅短时与渲染线程重叠，属可接受的轻微抖动，故标 @unchecked Sendable。
final class EQAudioTap: @unchecked Sendable {
    /// 预设名 -> [低音增益, 中音增益, 高音增益]（单位 dB）
    static let presets: [String: [Double]] = [
        "关闭":     [0, 0, 0],
        "低音增强": [8, 0, 2],
        "人声":     [2, 5, 3],
        "明亮":     [0, 2, 7],
        "摇滚":     [5, 3, 4],
    ]

    private struct Coeffs { var b0: Float = 0; var b1: Float = 0; var b2: Float = 0; var a1: Float = 0; var a2: Float = 0 }
    private var filters: [[Coeffs]] = []
    private var z1: [[Float]] = []
    private var z2: [[Float]] = []
    private var bands: [Double] = [0, 0, 0]
    private var sampleRate: Double = 44100
    private var channels: Int = 2

    func setBands(_ newBands: [Double]) {
        bands = newBands
        recompute()
    }

    func configure(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = max(1, channels)
        recompute()
    }

    private func recompute() {
        let freqs = [80.0, 1000.0, 10000.0]
        let q: Double = 1.0
        var newFilters: [[Coeffs]] = []
        for _ in 0..<channels {
            var chFilters: [Coeffs] = []
            for i in 0..<3 {
                let g = bands.count > i ? bands[i] : 0
                chFilters.append(peaking(sampleRate: sampleRate, freq: freqs[i], gainDB: g, q: q))
            }
            newFilters.append(chFilters)
        }
        filters = newFilters
        z1 = Array(repeating: Array(repeating: 0, count: 3), count: channels)
        z2 = Array(repeating: Array(repeating: 0, count: 3), count: channels)
    }

    /// RBJ 峰值滤波器系数（已按 a0 归一化，Transposed Direct Form II）
    private func peaking(sampleRate: Double, freq: Double, gainDB: Double, q: Double) -> Coeffs {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * freq / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2 * q)
        let b0 = 1 + alpha * A
        let b1 = -2 * cosw0
        let b2 = 1 - alpha * A
        let a0 = 1 + alpha / A
        let a1 = -2 * cosw0
        let a2 = 1 - alpha / A
        return Coeffs(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
                      a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    /// 对 AudioBufferList 做 in-place 三阶 Biquad 级联处理
    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, numberFrames: Int) {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let nch = min(channels, abl.count)
        for ch in 0..<nch {
            guard let data = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
            for band in 0..<3 {
                let c = filters[ch][band]
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
    }
}
