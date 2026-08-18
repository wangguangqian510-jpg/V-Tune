import SwiftUI
import UIKit
import Combine

struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false
    /// 拖动进度条时的临时位置（拖动中不跟播放进度，松手才真正 seek）。
    @State private var scrubTime: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: engine.currentCover.map { $0.opacity(0.9) } + [.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                artwork
                info
                progress
                controls
                volume
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
                Picker("预设", selection: $engine.eqPreset) {
                    ForEach(Array(EQAudioTap.presets.keys.sorted()), id: \.self) { name in
                        Text(name)
                    }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
                Text(engine.eqDiagnostic)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
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
                    Button { showLyrics = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
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
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
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
        var idx = 0
        for (i, l) in lines.enumerated() {
            if l.time <= t { idx = i } else { break }
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
