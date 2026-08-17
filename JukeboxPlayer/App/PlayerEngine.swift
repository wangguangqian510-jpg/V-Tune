import Foundation
import Combine
import UIKit
import SwiftUI
import MediaPlayer
import AVFoundation

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

    @Published var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    /// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机
    @Published var playbackMode: PlaybackMode = .order

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

        // 进度观察（4fps 基础更新，足够 UI；高频场景可另行监听）
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self = self else { return }
            let s = CMTimeGetSeconds(t)
            if s.isFinite {
                self.currentTime = s
                if s > self.duration { self.duration = s }
            }
        }

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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
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
        if reason == .oldDeviceUnavailable {
            player?.pause(); isPlaying = false
        }
    }
}

// MARK: - Helpers

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
