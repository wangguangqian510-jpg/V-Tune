import SwiftUI
import UIKit
import Combine
import AVKit
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
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
    /// 拖动进度条时的临时位置（拖动中不跟播放进度，松手才真正 seek）。
    @State private var scrubTime: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: engine.currentCover.map { $0.opacity(0.9) } + [.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

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
                    artwork
                }
                info
                progress
                controls
                volume
                playbackExtras
                eqPanel
                Spacer(minLength: 0)
                queueToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        .foregroundStyle(.white)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            engine.refreshEQDiagnostic()
        }

        if showQueue { queueSheet }
            if showLyrics { lyricsSheet }
        }
    }

    // MARK: Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.title3).foregroundStyle(.white)
            }
            Spacer()
            Text("正在播放").font(.headline)
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

    // MARK: Artwork (黑胶旋转)
    private var artwork: some View {
        VinylArtwork(cover: engine.currentCover, artwork: engine.artwork)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(engine.currentTime * 20))
            .animation(.linear, value: engine.currentTime)
            .shadow(radius: 20, y: 10)
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
                    get: { engine.isScrubbing ? scrubTime : engine.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        engine.isScrubbing = true
                        scrubTime = engine.currentTime
                    } else {
                        engine.seek(to: scrubTime)
                        engine.isScrubbing = false
                    }
                }
            )
            .tint(.white)

            HStack {
                Text(formatTime(engine.isScrubbing ? scrubTime : engine.currentTime)).font(.caption).foregroundStyle(.white.opacity(0.7))
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
                // 歌词操作：示例 / 粘贴 / 导入LRC / 清除（无歌词也能立刻验证偏移）
                HStack(spacing: 14) {
                    Button { engine.loadSampleLyricsForCurrent() } label: { Label("示例", systemImage: "lightbulb") }
                    Button { showPasteLyrics = true } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                    Button { showLRCImporter = true } label: { Label("导入LRC", systemImage: "square.and.arrow.down") }
                    Button { engine.setLyricsForCurrent("") } label: { Label("清除", systemImage: "trash") }
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
            allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .text, .text],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    engine.setLyricsForCurrent(text)
                }
            }
        }
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
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
                        let active = i == index(at: engine.currentTime)
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
            .onReceive(engine.$currentTime) { t in
                let idx = index(at: t)
                if idx != lastIndex {
                    lastIndex = idx
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
            .onAppear { proxy.scrollTo(index(at: engine.currentTime), anchor: .center) }
        }
    }
}
