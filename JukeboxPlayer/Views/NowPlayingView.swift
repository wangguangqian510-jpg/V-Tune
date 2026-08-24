import SwiftUI
import UIKit
import Combine
import AVKit
import UniformTypeIdentifiers

extension UTType {
    /// .lrc 歌词文件：注册为纯文本子类，使系统文件选择器能选中 .lrc
    static let lrc = UTType(filenameExtension: "lrc", conformingTo: .plainText) ?? .plainText
}

/// 读取歌词文件，自动探测编码：UTF-8 → GBK/GB18030（中文常见）→ Latin1，
/// 避免中文 LRC 因 GBK 编码导致 String(contentsOf: .utf8) 返回 nil 而静默导入失败。
private func readLyricsFile(_ url: URL) -> String? {
    let gbk = String.Encoding(rawValue: 0x80000632) // kCFStringEncodingGB_18030_2000，覆盖 GBK
    for enc in [String.Encoding.utf8, gbk, .isoLatin1] {
        if let s = try? String(contentsOf: url, encoding: enc),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
    }
    return nil
}

// MARK: - 在线歌词搜索（直连歌词源；原生 App 无 CORS 限制，无需中转代理）
private struct LyricsCandidate: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let provider: String
    /// api.lrc.cx 单结果已直接带 LRC；lrclib 若 search 已含 syncedLyrics 也填这里
    let lrc: String?
    /// lrclib 需要二次拉取详情时使用的 ID
    let lrclibId: Int?
}

private struct LyricsService {
    /// 在线搜歌词：先试 api.lrc.cx（中文友好，聚合网易云/QQ/酷狗），无结果/无时间轴再试 lrclib（国际，稳定）。
    static func search(title: String, artist: String) async throws -> [LyricsCandidate] {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1) api.lrc.cx：直接返回 LRC 正文
        if let txt = try? await fetchLRCCX(title: t, artist: a),
           !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           txt.range(of: #"\[\d{1,2}:\d{1,2}"#, options: .regularExpression) != nil {
            return [LyricsCandidate(title: t, artist: a, album: "", provider: "api.lrc.cx", lrc: txt, lrclibId: nil)]
        }
        // 2) lrclib：返回候选列表（含 syncedLyrics）
        if let list = try? await fetchLRCLib(title: t, artist: a), !list.isEmpty {
            return list
        }
        return []
    }

    /// 取某候选的完整 LRC 文本。
    static func fetchLyric(_ c: LyricsCandidate) async throws -> String {
        if let lrc = c.lrc, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lrc
        }
        if let id = c.lrclibId {
            return try await fetchLRCLibByID(id)
        }
        throw NSError(domain: "Lyrics", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "该候选无可用歌词"])
    }

    private static func fetchLRCCX(title: String, artist: String) async throws -> String? {
        guard var comp = URLComponents(string: "https://api.lrc.cx/lyrics") else { return nil }
        comp.queryItems = [URLQueryItem(name: "title", value: title),
                           URLQueryItem(name: "artist", value: artist)]
        guard let url = comp.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("YueYing/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8)
    }

    private static func fetchLRCLib(title: String, artist: String) async throws -> [LyricsCandidate] {
        guard var comp = URLComponents(string: "https://lrclib.net/api/search") else { return [] }
        comp.queryItems = [URLQueryItem(name: "track_name", value: title),
                           URLQueryItem(name: "artist_name", value: artist)]
        guard let url = comp.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("JukeboxPlayer/1.0 (https://github.com/wangguangqian510-jpg/moyuxuan)",
                     forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let trackName = d["trackName"] as? String else { return nil }
            let artistName = (d["artistName"] as? String) ?? ""
            let album = (d["albumName"] as? String) ?? ""
            let id = (d["id"] as? Int) ?? 0
            let synced = d["syncedLyrics"] as? String
            return LyricsCandidate(title: trackName, artist: artistName, album: album,
                                  provider: "lrclib", lrc: synced,
                                  lrclibId: synced == nil ? id : nil)
        }
    }

    private static func fetchLRCLibByID(_ id: Int) async throws -> String {
        guard let url = URL(string: "https://lrclib.net/api/get/\(id)") else {
            throw NSError(domain: "Lyrics", code: -3, userInfo: [NSLocalizedDescriptionKey: "无效 ID"])
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("YueYing/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Lyrics", code: -2, userInfo: [NSLocalizedDescriptionKey: "解析失败"])
        }
        if let synced = d["syncedLyrics"] as? String, !synced.isEmpty { return synced }
        if let plain = d["plainLyrics"] as? String, !plain.isEmpty { return plain }
        throw NSError(domain: "Lyrics", code: -2, userInfo: [NSLocalizedDescriptionKey: "该候选无可用歌词"])
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
    /// 高频进度订阅（独立发布通道，避免拖累全局页面）
    @EnvironmentObject private var playbackProgress: PlaybackProgress
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false
    /// 图形化 EQ 滑块展开状态
    @State private var showGraphicEQ = false
    /// MP4 视频全屏播放
    @State private var videoFullscreen = false
    /// 睡眠定时自定义输入
    @State private var showSleepAlert = false
    @State private var customSleepText = ""
    /// 歌词：粘贴 / 导入 LRC
    @State private var showPasteLyrics = false
    @State private var pasteLyricsText = ""
    @State private var showLRCImporter = false
    @State private var showMore = false
    /// 在线搜歌词
    @State private var showOnlineSearch = false
    @State private var onlineTitle = ""
    @State private var onlineArtist = ""
    @State private var onlineCandidates: [LyricsCandidate] = []
    @State private var onlineSearching = false
    @State private var onlineError: String?
    @State private var onlinePreview: String?
    @State private var onlineSearched = false
    /// 拖动进度条时的临时位置（拖动中不跟播放进度，松手才真正 seek）。
    @State private var scrubTime: Double = 0
    /// 自定义皮肤(单例): 开启时播放页背景换成用户图片
    @ObservedObject private var skin = SkinManager.shared

    /// 背景层: 皮肤图(可调模糊/暗度) 或 默认封面渐变
    @ViewBuilder
    private var backgroundLayer: some View {
        if skin.enabled, let img = skin.image {
            GeometryReader { geo in
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: skin.blur)
                    .overlay(Color.black.opacity(skin.dim))
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(colors: engine.currentCover.map { $0.opacity(0.9) } + [.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// 黑胶模式下是否隐藏封面渐变(让皮肤图透出来)。开启皮肤且关闭「黑胶衬底」时为 true。
    private var hideVinylGradient: Bool {
        skin.enabled && skin.image != nil && !skin.vinylBackdrop
    }

    var body: some View {
        ZStack {
            backgroundLayer
            GeometryReader { geo in
                Group {
                    if geo.size.width > geo.size.height {
                        landscapeLayout
                    } else {
            VStack(spacing: 24) {
                header
                if engine.isVideo {
                    ZStack(alignment: .topTrailing) {
                        VideoPlayer(player: engine.avPlayer)
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(radius: 20, y: 10)
                        Button {
                            videoFullscreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                                .padding(8)
                                .background(.black.opacity(0.45), in: Circle())
                                .foregroundStyle(.white)
                        }
                        .padding(10)
                    }
                    .fullScreenCover(isPresented: $videoFullscreen) {
                        ZStack(alignment: .topLeading) {
                            VideoPlayer(player: engine.avPlayer)
                                .background(.black)
                            Button {
                                videoFullscreen = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white)
                                    .padding()
                                    .background(.black.opacity(0.35), in: Circle())
                            }
                            .padding(.top, 8)
                        }
                        .background(.black)
                        .ignoresSafeArea()
                    }
                } else {
                    if hideVinylGradient {
                        // 纯皮肤模式: 不要黑胶圆盘, 封面卡片浮在皮肤图上
                        skinCoverCard
                    } else {
                        artwork
                        inlineLyrics
                    }
                }
                info
                progress
                controls
                volume
                moreSection
                Spacer(minLength: 0)
                queueToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        .foregroundStyle(.white)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            engine.refreshEQDiagnostic()
        }
        if showQueue { queueSheet }
            if showLyrics { lyricsSheet }
        if showOnlineSearch { onlineSearchSheet }
        }
        .gesture(dismissSwipe)
    }
    // MARK: Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 20) {
                Button { showLyrics.toggle() } label: {
                    Image(systemName: "text.quote").font(.title3).foregroundStyle(.white)
                }
                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet").font(.title3).foregroundStyle(.white)
                }
            }
        }
    }

    /// 水平滑动返回：在播放页空白/黑胶区域左右滑动即可回到主页。
    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                let w = value.translation.width
                let h = value.translation.height
                guard abs(w) > abs(h), abs(w) > 60 else { return }
                dismiss()
            }
    }

    /// 横屏：左右分栏 — 封面/视频占左列，控制区占右列，
    /// 解决竖屏布局硬挤进横屏时封面被挤压裁切的问题。
    private var landscapeLayout: some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(spacing: 20) {
                header
                if engine.isVideo {
                    VideoPlayer(player: engine.avPlayer)
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 20, y: 10)
                } else if hideVinylGradient {
                    skinCoverCard
                } else {
                    artwork
                    inlineLyrics
                        .frame(maxHeight: 120)
                }
                Spacer(minLength: 0)
                queueToggle
            }
            .frame(maxWidth: .infinity)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if !engine.isVideo { inlineLyrics.frame(maxHeight: 84) }
                    info
                    progress
                    controls
                    volume
                    moreSection
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    // MARK: Artwork (黑胶旋转)
    private var artwork: some View {
        // 黑胶旋转：用 TimelineView 每 1/30s 直接读 player.currentTime()（liveCurrentTime），
        // 不再依赖 engine.currentTime 的发布节流，彻底解决「有的歌曲播放中黑胶不转」的卡顿。
        TimelineView(.periodic(from: .now, by: 1/30)) { _ in
            VinylArtwork(cover: engine.currentCover, artwork: engine.artwork)
                .rotationEffect(.degrees(engine.liveCurrentTime * 20))
        }
        .frame(maxWidth: .infinity, maxHeight: 220)
        .aspectRatio(1, contentMode: .fit)
        .shadow(radius: 20, y: 10)
    }

    /// 纯皮肤模式的封面卡: 真实内嵌封面(或渐变占位)圆角卡片, 下方紧跟滚动歌词
    private var skinCoverCard: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: engine.currentCover,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    if let img = engine.artwork {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: 300)
                .aspectRatio(1, contentMode: .fit)
                .shadow(radius: 24, y: 12)
            inlineLyrics
        }
    }
    // MARK: Info
    private var info: some View {
        VStack(spacing: 6) {
            Text(engine.title).font(.title2.bold()).lineLimit(1)
            Text(engine.artist.isEmpty ? "未知艺术家" : engine.artist)
                .font(.headline.weight(.regular)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            if !engine.album.isEmpty {
                Text(engine.album).font(.subheadline).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
    }
    // MARK: Progress
    private var progress: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { engine.isScrubbing ? scrubTime : playbackProgress.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        engine.isScrubbing = true
                        scrubTime = playbackProgress.currentTime
                    } else {
                        engine.seek(to: scrubTime)
                        engine.isScrubbing = false
                    }
                }
            )
            .tint(.white)
            HStack {
                Text(formatTime(engine.isScrubbing ? scrubTime : playbackProgress.currentTime)).font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(formatTime(engine.duration)).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
    // MARK: Controls
    private var controls: some View {
        HStack(spacing: 28) {
            Button { engine.cyclePlaybackMode() } label: {
                Image(systemName: modeIcon).font(.title3).foregroundStyle(.white)
            }
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill").font(.title).foregroundStyle(.white)
            }
            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(.white)
            }
            Button { engine.next() } label: {
                Image(systemName: "forward.fill").font(.title).foregroundStyle(.white)
            }
        }
    }
    private var modeIcon: String {
        switch engine.playbackMode {
        case .order:   return "list.number"
        case .loop:    return "repeat"
        case .single:  return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
    // MARK: Volume
    private var volume: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(.white.opacity(0.7))
            Slider(value: $engine.volume, in: 0...1).tint(.white)
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.white.opacity(0.7))
        }
    }
    // MARK: EQ 音效面板（移到播放页，方便边听边调）
    private var eqPanel: some View {
        VStack(spacing: 10) {
            Toggle("均衡器 EQ", isOn: $engine.eqEnabled)
                .tint(.white)
                .font(.subheadline)
            if engine.eqEnabled {
                HStack {
                    Menu {
                        ForEach(Array(EQAudioTap.presets.keys.sorted()), id: \.self) { name in
                            Button(name) { engine.selectPreset(name) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("预设：\(engine.eqPreset)")
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        withAnimation { showGraphicEQ.toggle() }
                    } label: {
                        Image(systemName: showGraphicEQ ? "waveform.circle.fill" : "waveform.circle")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
                if showGraphicEQ {
                    graphicEQ
                }
                Text(engine.eqDiagnostic)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
    }
    /// 图形化 EQ：10 段竖向滑块（横向滚动），绑定 engine.eqBands。
    /// 改进：列宽加大、滑块行程加长更好拖；dB 读数独立成行且固定高度，永不被滑块拇指遮挡。
    private var graphicEQ: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(0..<EQAudioTap.bandCount, id: \.self) { i in
                    VStack(spacing: 6) {
                        // dB 读数独立成行：固定高度，滑块拉到顶端也不会盖住数字
                        Text("\(Int(engine.eqBands[i]))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(engine.eqBands[i] == 0 ? .white.opacity(0.45) : .yellow)
                            .frame(height: 14)
                        Slider(value: Binding(
                            get: { engine.eqBands[i] },
                            set: { engine.eqBands[i] = $0 }
                        ), in: -20...20)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 175)
                        .tint(.white)
                        Text(EQAudioTap.freqLabels[i])
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(width: 46)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 210)
    }
    // MARK: 播放增强（睡眠 / 速度 / AirPlay）
    private var playbackExtras: some View {
        HStack(spacing: 18) {
            // 睡眠定时
            Menu {
                ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                    Button("\(m) 分钟") { engine.setSleep(minutes: m) }
                }
                Divider()
                Button("自定义…") { showSleepAlert = true }
                Button("关闭") { engine.setSleep(minutes: nil) }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "moon.zzz.fill")
                    if engine.sleepRemaining > 0 {
                        Text(formatSleep(engine.sleepRemaining))
                            .font(.system(size: 9))
                    }
                }
                .foregroundStyle(.white)
            }
            // 播放速度
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                    Button(String(format: "%.2g×", r)) { engine.playbackRate = Float(r) }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "goforward")
                    Text(String(format: "%.2g×", engine.playbackRate))
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white)
            }
            // AirPlay 投送
            VStack(spacing: 2) {
                RoutePickerView()
                    .frame(width: 44, height: 30)
                Text("AirPlay")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white)
        }
        .font(.title3)
        .alert("自定义睡眠定时", isPresented: $showSleepAlert) {
            TextField("分钟", text: $customSleepText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) { customSleepText = "" }
            Button("确定") {
                if let m = Int(customSleepText), m > 0 { engine.setSleep(minutes: m) }
                customSleepText = ""
            }
        } message: {
            Text("设定 N 分钟后自动暂停播放")
        }
    }
    private func formatSleep(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return sec == 0 ? "\(m)m" : "\(m):\(String(format: "%02d", sec))"
    }
    // MARK: Queue
    private var queueToggle: some View {
        Text("\(modeName) · 共 \(engine.tracks.count) 首 · 第 \(engine.currentIndex + 1) 首")
            .font(.footnote).foregroundStyle(.white.opacity(0.6))
    }
    private var modeName: String {
        switch engine.playbackMode {
        case .order:   return "顺序"
        case .loop:    return "列表循环"
        case .single:  return "单曲循环"
        case .shuffle: return "随机"
        }
    }
    private var queueSheet: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("播放队列").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button { showQueue = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(engine.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                isCurrent: index == engine.currentIndex,
                                isPlaying: engine.isPlaying,
                                onTap: {
                                    engine.play(index: index)
                                    showQueue = false
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .bottom))
    }
    // MARK: Lyrics
    private var lyricsSheet: some View {
        let parsed = engine.lyrics.flatMap { parseLRC($0) }
        return ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("歌词").font(.headline).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 10) {
                        Button { engine.lyricsOffset -= 0.5 } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.white.opacity(0.8))
                        }
                        Text(String(format: "%+.1fs", engine.lyricsOffset))
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                            .frame(minWidth: 44)
                        Button { engine.lyricsOffset += 0.5 } label: {
                            Image(systemName: "plus.circle").foregroundStyle(.white.opacity(0.8))
                        }
                        Button { showLyrics = false } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding()
                // 歌词操作收纳：示例独立保留，粘贴/在线搜/清除折叠进「更多」菜单（排版整洁）
                HStack(spacing: 14) {
                    Button { engine.loadSampleLyricsForCurrent() } label: { Label("示例", systemImage: "lightbulb") }
                    Spacer()
                    Menu {
                        Button { showPasteLyrics = true } label: { Label("粘贴歌词 / LRC", systemImage: "doc.on.clipboard") }
                        Button {
                            onlineTitle = engine.title
                            onlineArtist = engine.artist
                            onlineCandidates = []
                            onlinePreview = nil
                            onlineError = nil
                            onlineSearched = false
                            showOnlineSearch = true
                        } label: { Label("在线搜歌词", systemImage: "globe") }
                        Divider()
                        Button(role: .destructive) { engine.setLyricsForCurrent("") } label: { Label("清除歌词", systemImage: "trash") }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal)
                .padding(.bottom, 8)
                if let parsed = parsed, !parsed.isEmpty {
                    LyricsView(lines: parsed).environmentObject(engine)
                } else if let lyrics = engine.lyrics, !lyrics.isEmpty {
                    ScrollView {
                        Text(lyrics)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                    }
                } else {
                    Text("暂无歌词")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
        }
        .transition(.move(edge: .bottom))
        .sheet(isPresented: $showPasteLyrics) {
            NavigationView {
                VStack(spacing: 0) {
                    TextEditor(text: $pasteLyricsText)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity)
                }
                .navigationTitle("粘贴歌词 / LRC")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { showPasteLyrics = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") {
                            engine.setLyricsForCurrent(pasteLyricsText)
                            showPasteLyrics = false
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showLRCImporter,
            // .lrc 不是系统预置类型，直接用 .plainText / .text 保证所有系统都能选到，
            // 进来后再按扩展名过滤，避免 .txt 小说等被误当歌词。
            allowedContentTypes: [.lrc, .plainText, .text, .utf8PlainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let ext = url.pathExtension.lowercased()
                guard ["lrc", "txt"].contains(ext) else {
                    // 不影响体验：非 lrc/txt 静默忽略即可
                    return
                }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                if let text = readLyricsFile(url) {
                    engine.setLyricsForCurrent(text)
                }
            }
        }
    }

    // MARK: 在线搜歌词（分层全屏视图，风格与 lyricsSheet 一致）
    private var onlineSearchSheet: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("在线搜歌词").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button { showOnlineSearch = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                HStack(spacing: 8) {
                    TextField("歌名", text: $onlineTitle).textFieldStyle(.roundedBorder)
                    TextField("歌手", text: $onlineArtist).textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                Button {
                    Task { await runOnlineSearch() }
                } label: {
                    if onlineSearching { ProgressView().tint(.white) }
                    else { Label("搜索", systemImage: "magnifyingglass") }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if let err = onlineError, onlinePreview == nil {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }

                if onlineSearching, onlinePreview == nil {
                    ProgressView("搜索中…").tint(.white).padding()
                } else if let preview = onlinePreview, !preview.isEmpty {
                    ScrollView {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    Button {
                        engine.setLyricsForCurrent(preview)
                        showOnlineSearch = false
                        showLyrics = false
                    } label: { Label("应用到本曲", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                } else if !onlineCandidates.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(onlineCandidates) { c in
                                Button {
                                    Task { await pickOnlineCandidate(c) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).font(.headline).foregroundStyle(.white)
                                        let sub = "\(c.artist)\(c.album.isEmpty ? "" : " · \(c.album)")"
                                        if !sub.trimmingCharacters(in: .whitespaces).isEmpty {
                                            Text(sub).font(.caption).foregroundStyle(.white.opacity(0.6))
                                        }
                                        Text(c.provider).font(.caption2).foregroundStyle(.white.opacity(0.4))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                } else if !onlineSearching, onlineSearched {
                    Text("未找到歌词，换个歌名/歌手试试")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if !onlineSearching {
                    Text("输入歌名 / 歌手后点「搜索」")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
                Spacer(minLength: 0)
            }
        }
        .transition(.move(edge: .bottom))
    }

    @MainActor
    private func runOnlineSearch() async {
        onlineError = nil
        onlinePreview = nil
        onlineCandidates = []
        onlineSearching = true
        onlineSearched = true
        defer { onlineSearching = false }
        do {
            let res = try await LyricsService.search(title: onlineTitle, artist: onlineArtist)
            if res.count == 1, let lrc = res[0].lrc, !lrc.isEmpty {
                onlinePreview = lrc
            } else {
                onlineCandidates = res
                if res.isEmpty { onlineError = "未找到歌词" }
            }
        } catch {
            onlineError = "搜索失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func pickOnlineCandidate(_ c: LyricsCandidate) async {
        onlineError = nil
        onlineSearching = true
        defer { onlineSearching = false }
        do {
            let lrc = try await LyricsService.fetchLyric(c)
            onlinePreview = lrc
        } catch {
            onlineError = "获取失败：\(error.localizedDescription)"
        }
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private var inlineLyrics: some View {
        let parsed = engine.lyrics.flatMap { parseLRC($0) }
        return Group {
            if let parsed = parsed, !parsed.isEmpty {
                LyricsView(lines: parsed).environmentObject(engine)
                    .frame(maxHeight: 140)
            } else if let lyrics = engine.lyrics, !lyrics.isEmpty {
                ScrollView {
                    Text(lyrics)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
                .frame(maxHeight: 140)
            } else {
                HStack {
                    Spacer()
                    Text("暂无歌词 · 点右上角 🌐 在线搜")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .frame(height: 40)
            }
        }
    }

    // MARK: 更多设置（收纳 EQ / 睡眠 / 倍速 / 投屏，默认折叠）
    private var moreSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation { showMore.toggle() }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("更多设置（EQ / 睡眠 / 倍速 / 投屏）")
                    Spacer()
                    Image(systemName: showMore ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline)
                .foregroundStyle(.white)
            }
            if showMore {
                eqPanel
                playbackExtras
            }
        }
    }
}
// MARK: - AirPlay 投送按钮
private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = .systemBlue
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
// MARK: - 黑胶唱片视图
private struct VinylArtwork: View {
    let cover: [Color]
    let artwork: UIImage?
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // 黑胶盘体：深色 + 环纹光泽
                Circle()
                    .fill(AngularGradient(
                        colors: [.black, Color(white: 0.28), .black, Color(white: 0.28), .black],
                        center: .center))
                    .frame(width: size, height: size)
                // 中心封面（圆形，略小于盘体）
                Circle()
                    .fill(LinearGradient(colors: cover,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.60, height: size * 0.60)
                    .overlay {
                        if let img = artwork {
                            Image(uiImage: img).resizable().scaledToFill()
                                .clipShape(Circle())
                        }
                    }
                // 中心孔
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.05, height: size * 0.05)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
// MARK: - LRC 歌词解析与逐行视图
private struct LRCLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}
/// 解析 LRC 文本（[mm:ss.xx] 或 [mm:ss] 时间标签）。返回 nil 表示不是 LRC 格式（纯文本歌词）。
private func parseLRC(_ raw: String) -> [LRCLine]? {
    guard let re = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2}(?:\\.\\d{1,3})?)\\]") else { return nil }
    var out: [LRCLine] = []
    for line in raw.components(separatedBy: "\n") {
        let ns = line as NSString
        let matches = re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { continue }
        let last = matches.last!
        var text = ns.substring(from: last.range.location + last.range.length)
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty { text = "♪" }
        for m in matches {
            guard m.numberOfRanges >= 3 else { continue }
            guard let minRange = Range(m.range(at: 1), in: line),
                  let secRange = Range(m.range(at: 2), in: line),
                  let min = Int(line[minRange]),
                  let sec = Double(line[secRange]) else { continue }
            out.append(LRCLine(time: Double(min) * 60 + sec, text: text))
        }
    }
    return out.isEmpty ? nil : out.sorted { $0.time < $1.time }
}
/// LRC 逐行歌词：当前播放行加粗高亮，并自动滚动到屏幕中央。
/// 用 onReceive(engine.$currentTime) 而非 onChange —— 后者两参数闭包是 iOS 17+ API，
/// 在部署目标 16.0 下会触发可用性编译错误。
private struct LyricsView: View {
    let lines: [LRCLine]
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var playbackProgress: PlaybackProgress
    @State private var lastIndex: Int = 0
    private func index(at t: Double) -> Int {
        let tt = max(0, t + engine.lyricsOffset)
        var idx = 0
        for (i, l) in lines.enumerated() {
            if l.time <= tt { idx = i } else { break }
        }
        return idx
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(0..<lines.count, id: \.self) { i in
                        let active = i == index(at: playbackProgress.currentTime)
                        Text(lines[i].text)
                            .font(active ? .title3.bold() : .body)
                            .foregroundStyle(active ? .white : .white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .id(i)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 40)
            }
            .onReceive(playbackProgress.$currentTime) { t in
                let idx = index(at: t)
                if idx != lastIndex {
                    lastIndex = idx
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
            .onAppear { proxy.scrollTo(index(at: playbackProgress.currentTime), anchor: .center) }
        }
    }

    // MARK: 内联歌词（黑胶下方直接显示，随播放高亮当前行）
}
