//
//  Jukebox.swift
//  JukeboxPlayer
//
//  Modernized port of teodorpatras/Jukebox (https://github.com/teodorpatras/Jukebox)
//  Original copyright (c) 2015 Teodor Patraş — MIT License.
//  Ported to Swift 5.9 / iOS 16: AVAudioSession modern API, MPMediaItemArtwork
//  boundsSize initializer, AVMetadataKey enum cases, @objc notification handlers,
//  CMTime helpers, and collection APIs.
//

import Foundation
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - Delegate protocols

public protocol JukeboxDelegate: AnyObject {
    func jukeboxStateDidChange(_ jukebox: Jukebox)
    func jukeboxPlaybackProgressDidChange(_ jukebox: Jukebox)
    func jukeboxDidLoadItem(_ jukebox: Jukebox, item: JukeboxItem)
    func jukeboxDidUpdateMetadata(_ jukebox: Jukebox, forItem: JukeboxItem)
}

protocol JukeboxItemDelegate: AnyObject {
    func jukeboxItemDidLoadPlayerItem(_ item: JukeboxItem)
    func jukeboxItemDidUpdate(_ item: JukeboxItem)
    func jukeboxItemDidFail(_ item: JukeboxItem)
}

// MARK: - JukeboxItem

open class JukeboxItem: NSObject {

    public struct Meta {
        public var duration: Double?
        public var title: String?
        public var album: String?
        public var artist: String?
        public var artwork: UIImage?
    }

    // MARK: Properties

    public let identifier: String
    public let url: URL
    public var localTitle: String?
    public private(set) var playerItem: AVPlayerItem?
    public private(set) var currentTime: Double?
    public private(set) lazy var meta = Meta()

    weak var delegate: JukeboxItemDelegate?
    private var didLoad = false
    private var timer: Timer?
    private let observedValue = "timedMetadata"

    // MARK: Initializer

    public required init(url: URL, localTitle: String? = nil) {
        self.url = url
        self.identifier = UUID().uuidString
        self.localTitle = localTitle
        super.init()
        configureMetadata()
    }

    open override var description: String {
        return "<JukeboxItem:\ntitle: \(meta.title ?? "")\nalbum: \(meta.album ?? "")\nartist: \(meta.artist ?? "")\nduration: \(meta.duration ?? 0)\ncurrentTime: \(currentTime ?? 0)\nurl: \(url)>"
    }

    override open func observeValue(forKeyPath keyPath: String?,
                                    of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?,
                                    context: UnsafeMutableRawPointer?) {
        if keyPath == observedValue {
            if let item = playerItem, item === (object as? AVPlayerItem) {
                let metadata = item.asset.metadata
                for m in metadata {
                    meta.process(metaItem: m)
                }
            }
            scheduleNotification()
        }
    }

    deinit {
        playerItem?.removeObserver(self, forKeyPath: observedValue)
    }

    // MARK: Internal methods

    func loadPlayerItem() {
        if let item = playerItem {
            refreshPlayerItem(withAsset: item.asset)
            delegate?.jukeboxItemDidLoadPlayerItem(self)
            return
        } else if didLoad {
            return
        } else {
            didLoad = true
        }

        loadAsync { asset in
            if self.validateAsset(asset) {
                self.refreshPlayerItem(withAsset: asset)
                self.delegate?.jukeboxItemDidLoadPlayerItem(self)
            } else {
                self.didLoad = false
                self.delegate?.jukeboxItemDidFail(self)
            }
        }
    }

    func refreshPlayerItem(withAsset asset: AVAsset) {
        playerItem?.removeObserver(self, forKeyPath: observedValue)
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.addObserver(self, forKeyPath: observedValue, options: .new, context: nil)
        update()
    }

    func update() {
        if let item = playerItem {
            let dur = CMTimeGetSeconds(item.asset.duration)
            meta.duration = dur.isFinite ? dur : nil
            let cur = CMTimeGetSeconds(item.currentTime())
            currentTime = cur.isFinite ? cur : nil
        }
    }

    // MARK: Private methods

    private func validateAsset(_ asset: AVURLAsset) -> Bool {
        var error: NSError?
        let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)
        if playableStatus != .loaded {
            print("[JukeboxItem] asset not playable: \(error?.localizedDescription ?? "unknown error")")
            return false
        }
        asset.statusOfValue(forKey: "duration", error: &error)
        if let error = error {
            if error.code == -1022 {
                fatalError("\n\n***** Jukebox fatal error *****\nIt looks like the asset cannot be loaded from the HTTP URL: \"\(url)\".\nEnable NSAppTransportSecurity -> NSAllowsArbitraryLoads in your Info.plist for HTTP streams.\n")
            }
            print("[JukeboxItem] duration load error: \(error.localizedDescription)")
            return false
        }
        return true
    }

    private func scheduleNotification() {
        timer?.invalidate()
        timer = nil
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.delegate?.jukeboxItemDidUpdate(self)
        }
    }

    private func loadAsync(_ completion: @escaping (AVURLAsset) -> Void) {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "commonMetadata"]) {
            DispatchQueue.main.async { completion(asset) }
        }
    }

    private func configureMetadata() {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["commonMetadata"]) {
            var error: NSError?
            guard asset.statusOfValue(forKey: "commonMetadata", error: &error) == .loaded else { return }
            let metadata = asset.commonMetadata
            for m in metadata {
                self.meta.process(metaItem: m)
            }
            DispatchQueue.main.async { self.scheduleNotification() }
        }
    }
}

private extension JukeboxItem.Meta {
    mutating func process(metaItem item: AVMetadataItem) {
        switch item.commonKey {
        case .commonKeyTitle:
            title = item.value as? String
        case .commonKeyAlbumName:
            album = item.value as? String
        case .commonKeyArtist:
            artist = item.value as? String
        case .commonKeyArtwork:
            processArtwork(fromMetadataItem: item)
        default:
            break
        }
    }

    mutating func processArtwork(fromMetadataItem item: AVMetadataItem) {
        guard let value = item.value else { return }
        if let data = value as? Data {
            artwork = UIImage(data: data)
        } else if let dict = value as? [AnyHashable: Any], let data = dict["data"] as? Data {
            artwork = UIImage(data: data)
        }
    }
}

// MARK: - Playback mode

/// 播放模式：顺序 / 列表循环 / 单曲循环 / 随机
public enum PlaybackMode: Int, Codable {
    case order = 0   // 顺序播放
    case loop = 1    // 列表循环
    case single = 2  // 单曲循环
    case shuffle = 3 // 随机播放
}

// MARK: - Jukebox

open class Jukebox: NSObject, JukeboxItemDelegate {

    public enum State: Int, CustomStringConvertible {
        case ready = 0
        case playing
        case paused
        case loading
        case failed

        public var description: String {
            switch self {
            case .ready:   return "Ready"
            case .playing: return "Playing"
            case .failed:  return "Failed"
            case .paused:  return "Paused"
            case .loading: return "Loading"
            }
        }
    }

    // MARK: Properties

    public var playbackMode: PlaybackMode = .order

    private var player: AVPlayer?
    private var progressObserver: Any?
    private var backgroundIdentifier: UIBackgroundTaskIdentifier = .invalid
    public private(set) weak var delegate: JukeboxDelegate?

    public private(set) var playIndex = 0
    public private(set) var queuedItems: [JukeboxItem]!
    public private(set) var state = State.ready {
        didSet { delegate?.jukeboxStateDidChange(self) }
    }

    // MARK: Computed

    open var volume: Float {
        get { player?.volume ?? 0 }
        set { player?.volume = newValue }
    }

    open var currentItem: JukeboxItem? {
        guard playIndex >= 0, playIndex < queuedItems.count else { return nil }
        return queuedItems[playIndex]
    }

    private var playerOperational: Bool {
        return player != nil && currentItem != nil
    }

    // MARK: Initializer

    public required init(delegate: JukeboxDelegate? = nil, items: [JukeboxItem] = [JukeboxItem]()) {
        self.delegate = delegate
        super.init()

        do {
            try configureAudioSession()
        } catch {
            print("[Jukebox - AudioSession] \(error)")
        }

        assignQueuedItems(items)
        configureObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: JukeboxItemDelegate

    func jukeboxItemDidFail(_ item: JukeboxItem) {
        stop()
        state = .failed
        delegate?.jukeboxStateDidChange(self)
    }

    func jukeboxItemDidUpdate(_ item: JukeboxItem) {
        guard currentItem != nil else { return }
        updateInfoCenter()
        delegate?.jukeboxDidUpdateMetadata(self, forItem: item)
    }

    func jukeboxItemDidLoadPlayerItem(_ item: JukeboxItem) {
        delegate?.jukeboxDidLoadItem(self, item: item)
        let index = queuedItems.firstIndex { $0 === item }
        guard let playItem = item.playerItem, state == .loading, playIndex == index else { return }
        registerForPlayToEndNotification(withItem: playItem)
        startNewPlayer(forItem: playItem)
    }

    // MARK: - Public methods

    public func play() {
        play(atIndex: playIndex)
    }

    public func play(atIndex index: Int) {
        guard index < queuedItems.count, index >= 0 else { return }

        configureBackgroundAudioTask()

        if queuedItems[index].playerItem != nil, playIndex == index {
            resumePlayback()
        } else {
            if let item = currentItem?.playerItem {
                unregisterForPlayToEndNotification(withItem: item)
            }
            playIndex = index

            if let asset = queuedItems[index].playerItem?.asset {
                playCurrentItem(withAsset: asset)
            } else {
                loadPlaybackItem()
            }

            preloadNextAndPrevious(atIndex: playIndex)
        }
        updateInfoCenter()
    }

    public func pause() {
        stopProgressTimer()
        player?.pause()
        state = .paused
    }

    public func stop() {
        invalidatePlayback()
        state = .ready
        UIApplication.shared.endBackgroundTask(backgroundIdentifier)
        backgroundIdentifier = .invalid
    }

    public func replay() {
        guard playerOperational else { return }
        stopProgressTimer()
        seek(toSecond: 0)
        play(atIndex: 0)
    }

    public func playNext() {
        guard playerOperational else { return }
        if let idx = nextIndex(from: playIndex) {
            play(atIndex: idx)
        } else {
            stop()
        }
    }

    public func playPrevious() {
        guard playerOperational else { return }
        if let idx = prevIndex(from: playIndex) {
            play(atIndex: idx)
        } else {
            stop()
        }
    }

    public func replayCurrentItem() {
        guard playerOperational else { return }
        seek(toSecond: 0, shouldPlay: true)
    }

    public func seek(toSecond second: Int, shouldPlay: Bool = false) {
        guard let player = player, let item = currentItem else { return }

        player.seek(to: CMTime(value: Int64(second), timescale: 1))
        item.update()
        if shouldPlay {
            player.play()
            if state != .playing { state = .playing }
        }
        delegate?.jukeboxPlaybackProgressDidChange(self)
    }

    public func append(item: JukeboxItem, loadingAssets: Bool) {
        queuedItems.append(item)
        item.delegate = self
        if loadingAssets {
            item.loadPlayerItem()
        }
    }

    public func remove(item: JukeboxItem) {
        if let index = queuedItems.firstIndex(where: { $0.identifier == item.identifier }) {
            queuedItems.remove(at: index)
        }
    }

    public func removeItems(withURL url: URL) {
        let indexes = queuedItems.enumerated().compactMap { $0.element.url == url ? $0.offset : nil }
        for index in indexes.reversed() {
            queuedItems.remove(at: index)
        }
    }

    // MARK: - Private methods

    // MARK: Playback

    private func updateInfoCenter() {
        guard let item = currentItem else { return }

        let title = (item.meta.title ?? item.localTitle) ?? item.url.lastPathComponent
        let currentTime = item.currentTime ?? 0
        let duration = item.meta.duration ?? 0

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: duration),
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: currentTime),
            MPNowPlayingInfoPropertyPlaybackQueueCount: NSNumber(value: queuedItems.count),
            MPNowPlayingInfoPropertyPlaybackQueueIndex: NSNumber(value: playIndex),
            MPMediaItemPropertyMediaType: NSNumber(value: MPMediaType.anyAudio.rawValue)
        ]

        if let artist = item.meta.artist {
            nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        }
        if let album = item.meta.album {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
        }
        if let img = item.meta.artwork {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func playCurrentItem(withAsset asset: AVAsset) {
        queuedItems[playIndex].refreshPlayerItem(withAsset: asset)
        startNewPlayer(forItem: queuedItems[playIndex].playerItem!)
        guard let playItem = queuedItems[playIndex].playerItem else { return }
        registerForPlayToEndNotification(withItem: playItem)
    }

    private func resumePlayback() {
        if state != .playing {
            startProgressTimer()
            if let player = player {
                player.play()
            } else {
                currentItem!.refreshPlayerItem(withAsset: currentItem!.playerItem!.asset)
                startNewPlayer(forItem: currentItem!.playerItem!)
            }
            state = .playing
        }
    }

    private func invalidatePlayback(shouldResetIndex resetIndex: Bool = true) {
        stopProgressTimer()
        player?.pause()
        player = nil

        if resetIndex {
            playIndex = 0
        }
    }

    private func startNewPlayer(forItem item: AVPlayerItem) {
        invalidatePlayback(shouldResetIndex: false)
        player = AVPlayer(playerItem: item)
        player?.allowsExternalPlayback = false
        startProgressTimer()
        seek(toSecond: 0, shouldPlay: true)
        updateInfoCenter()
    }

    // MARK: Items related

    private func assignQueuedItems(_ items: [JukeboxItem]) {
        queuedItems = items
        for item in queuedItems {
            item.delegate = self
        }
    }

    private func loadPlaybackItem() {
        guard playIndex >= 0, playIndex < queuedItems.count else { return }

        stopProgressTimer()
        player?.pause()
        queuedItems[playIndex].loadPlayerItem()
        state = .loading
    }

    private func preloadNextAndPrevious(atIndex index: Int) {
        guard !queuedItems.isEmpty else { return }

        if index - 1 >= 0 {
            queuedItems[index - 1].loadPlayerItem()
        }
        if index + 1 < queuedItems.count {
            queuedItems[index + 1].loadPlayerItem()
        }
    }

    // MARK: Playback mode index math

    private func nextIndex(from index: Int) -> Int? {
        let count = queuedItems.count
        guard count > 0 else { return nil }
        switch playbackMode {
        case .order:    return index + 1 < count ? index + 1 : nil
        case .loop:     return (index + 1) % count
        case .single:   return (index + 1) % count
        case .shuffle:
            if count == 1 { return index }
            var r = index
            while r == index { r = Int.random(in: 0..<count) }
            return r
        }
    }

    private func prevIndex(from index: Int) -> Int? {
        let count = queuedItems.count
        guard count > 0 else { return nil }
        switch playbackMode {
        case .order:    return index - 1 >= 0 ? index - 1 : nil
        case .loop:     return (index - 1 + count) % count
        case .single:   return (index - 1 + count) % count
        case .shuffle:
            if count == 1 { return index }
            var r = index
            while r == index { r = Int.random(in: 0..<count) }
            return r
        }
    }

    // MARK: Progress tracking

    private func startProgressTimer() {
        guard let player = player,
              let item = player.currentItem,
              CMTIME_IS_VALID(item.duration) else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] _ in
            self?.timerAction()
        } as Any
    }

    private func stopProgressTimer() {
        guard let player = player, let observer = progressObserver else { return }
        player.removeTimeObserver(observer)
        progressObserver = nil
    }

    // MARK: Configurations

    private func configureBackgroundAudioTask() {
        backgroundIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
            if let self = self {
                UIApplication.shared.endBackgroundTask(self.backgroundIdentifier)
                self.backgroundIdentifier = .invalid
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func configureObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleStall),
                                               name: .AVPlayerItemPlaybackStalled,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioSessionInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
    }

    // MARK: Notifications

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawType = (userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch interruptionType {
        case .began:
            pause()
        case .ended:
            if let rawOption = (userInfo[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue,
               AVAudioSession.InterruptionOptions(rawValue: rawOption).contains(.shouldResume) {
                resumePlayback()
            }
        @unknown default:
            break
        }
    }

    @objc private func handleStall() {
        player?.pause()
        player?.play()
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        if playbackMode == .single {
            replayCurrentItem()
            return
        }
        if let idx = nextIndex(from: playIndex) {
            play(atIndex: idx)
        } else {
            stop()
        }
    }

    private func timerAction() {
        guard player?.currentItem != nil else { return }
        currentItem?.update()
        guard currentItem?.currentTime != nil else { return }
        delegate?.jukeboxPlaybackProgressDidChange(self)
    }

    private func registerForPlayToEndNotification(withItem item: AVPlayerItem) {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playerItemDidPlayToEnd(_:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: item)
    }

    private func unregisterForPlayToEndNotification(withItem item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: item)
    }
}
