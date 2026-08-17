import Foundation
import Combine
import UIKit
import SwiftUI
import MediaPlayer

/// 播放引擎：封装 Jukebox，桥接到 SwiftUI（ObservableObject），
/// 同时接入 MPRemoteCommandCenter（锁屏 / 控制中心 / 耳机线控）。
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
    @Published private(set) var lastError: String?

    @Published var volume: Float = 1.0 {
        didSet { jukebox?.volume = volume }
    }

    /// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机
    @Published var playbackMode: PlaybackMode = .order {
        didSet { jukebox?.playbackMode = playbackMode }
    }

    private var jukebox: Jukebox?

    init() {
        setupRemoteCommands()
    }

    // MARK: - 播放列表

    func load(_ tracks: [Track]) {
        // 队列未变化且已存在时跳过重建，避免每次导入/点击都重置播放状态。
        if jukebox != nil, self.tracks.map(\.id) == tracks.map(\.id) { return }
        self.tracks = tracks
        let items = tracks.map { JukeboxItem(url: $0.url, localTitle: $0.title) }
        jukebox = Jukebox(delegate: self, items: items)
        jukebox?.playbackMode = playbackMode
        currentIndex = 0
        updateNowPlaying()
    }

    var hasTrack: Bool { !(jukebox?.queuedItems.isEmpty ?? true) }

    var currentCover: [Color] {
        if let track = tracks[safe: currentIndex] { return track.cover }
        return [.gray, .gray]
    }

    // MARK: - 控制

    func play(index: Int? = nil) {
        if let index = index { currentIndex = index }
        jukebox?.play(atIndex: currentIndex)
    }

    func togglePlay() {
        guard let jukebox = jukebox else { return }
        if jukebox.state == .playing { jukebox.pause() }
        else { jukebox.play() }
    }

    /// 循环切换播放模式：顺序 → 列表循环 → 单曲循环 → 随机
    func cyclePlaybackMode() {
        let order: [PlaybackMode] = [.order, .loop, .single, .shuffle]
        guard let i = order.firstIndex(of: playbackMode) else { playbackMode = .order; return }
        playbackMode = order[(i + 1) % order.count]
    }

    func next() { jukebox?.playNext() }
    func previous() { jukebox?.playPrevious() }

    func seek(to second: Double) {
        jukebox?.seek(toSecond: Int(second), shouldPlay: isPlaying)
    }

    // MARK: - 状态同步

    private func syncState() {
        guard let jukebox = jukebox else { return }
        isPlaying = (jukebox.state == .playing)
        currentIndex = jukebox.playIndex
        if jukebox.state == .failed {
            lastError = "当前曲目无法播放，请检查网络链接或本地文件是否有效"
        } else {
            lastError = nil
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let item = jukebox?.currentItem else { return }
        // 优先使用 AVAsset 解析到的动态元数据；解析不到时回退到 Track 的本地元数据。
        let localTrack = tracks[safe: currentIndex]
        title = item.meta.title ?? item.localTitle ?? localTrack?.title ?? item.url.lastPathComponent
        artist = item.meta.artist ?? localTrack?.artist ?? ""
        album = item.meta.album ?? localTrack?.album ?? ""
        artwork = item.meta.artwork
        duration = item.meta.duration ?? 0
        currentTime = item.currentTime ?? 0
    }

    // MARK: - 远程控制（锁屏 / 控制中心）

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.jukebox?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.jukebox?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.jukebox?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.jukebox?.playPrevious() }
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
}

// MARK: - JukeboxDelegate

extension PlayerEngine: JukeboxDelegate {
    nonisolated func jukeboxStateDidChange(_ jukebox: Jukebox) {
        Task { @MainActor in self.syncState() }
    }

    nonisolated func jukeboxPlaybackProgressDidChange(_ jukebox: Jukebox) {
        Task { @MainActor in
            self.currentTime = jukebox.currentItem?.currentTime ?? 0
            if let d = jukebox.currentItem?.meta.duration { self.duration = d }
        }
    }

    nonisolated func jukeboxDidLoadItem(_ jukebox: Jukebox, item: JukeboxItem) {
        Task { @MainActor in self.updateNowPlaying() }
    }

    nonisolated func jukeboxDidUpdateMetadata(_ jukebox: Jukebox, forItem: JukeboxItem) {
        Task { @MainActor in self.updateNowPlaying() }
    }
}

// MARK: - Helpers

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
