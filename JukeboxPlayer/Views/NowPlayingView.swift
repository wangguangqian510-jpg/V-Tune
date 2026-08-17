import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            LinearGradient(colors: engine.currentCover.map { $0.opacity(0.9) } + [.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Group {
                    if showLyrics {
                        lyricsView
                    } else {
                        artwork
                    }
                }
                info
                progress
                controls
                volume
                Spacer(minLength: 0)
                queueToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .foregroundStyle(.white)

            if showQueue { queueSheet }
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
            Button { showQueue.toggle() } label: {
                Image(systemName: "list.bullet").font(.title3).foregroundStyle(.white)
            }
        }
    }

    // MARK: Artwork (黑胶唱片，点击切换歌词)
    private var artwork: some View {
        GeometryReader { geo in
            let size = geo.size.width
            let coverSize = size * 0.62
            ZStack {
                Circle()
                    .fill(vinylGradient)
                    .frame(width: size, height: size)
                    .shadow(radius: 20, y: 10)
                Circle()
                    .fill(LinearGradient(colors: engine.currentCover,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: coverSize, height: coverSize)
                    .overlay {
                        if let img = engine.artwork {
                            Image(uiImage: img).resizable().scaledToFill()
                                .clipShape(Circle())
                        }
                    }
                    .shadow(radius: 8)
                Circle()
                    .fill(.black)
                    .frame(width: size * 0.06, height: size * 0.06)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 旋转角度绑定播放时间：播放时推进、暂停时停在当前角度。
            .rotationEffect(.degrees(engine.currentTime * 20))
            .animation(.linear(duration: 0.4), value: engine.currentTime)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .onTapGesture { withAnimation { showLyrics.toggle() } }
    }

    private var vinylGradient: AngularGradient {
        AngularGradient(colors: [Color(white: 0.08), Color(white: 0.24), Color(white: 0.08),
                                 Color(white: 0.24), Color(white: 0.08)],
                        center: .center)
    }

    // MARK: Lyrics (LRC)
    private var lyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if currentLyrics.isEmpty {
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text("暂无歌词")
                            .font(.headline).foregroundStyle(.white.opacity(0.5))
                        Text("导入带歌词的音频，或导入含 lyrics 字段的歌单即可显示")
                            .font(.caption).foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 18) {
                        Color.clear.frame(height: 24)
                        ForEach(currentLyrics) { line in
                            let isCurrent = (currentLineIndex.flatMap { currentLyrics[$0].id } == line.id)
                            Text(line.text)
                                .font(isCurrent ? .title3.bold() : .body)
                                .foregroundStyle(isCurrent ? .white : .white.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .id(line.id)
                                .animation(.easeInOut, value: isCurrent)
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { withAnimation { showLyrics.toggle() } }
            .onChange(of: currentLineIndex) { _ in scrollLyrics(proxy) }
            .onChange(of: engine.currentIndex) { _ in scrollLyrics(proxy) }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    private func scrollLyrics(_ proxy: ScrollViewProxy) {
        guard let idx = currentLineIndex else { return }
        withAnimation { proxy.scrollTo(currentLyrics[idx].id, anchor: .center) }
    }

    private var currentLyrics: [LRCLine] {
        guard let lyrics = engine.tracks[safe: engine.currentIndex]?.lyrics, !lyrics.isEmpty else { return [] }
        return parseLRC(lyrics)
    }

    private var currentLineIndex: Int? {
        let t = engine.currentTime
        return currentLyrics.lastIndex { $0.time <= t }
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
            Slider(value: Binding(get: { engine.currentTime },
                                  set: { engine.seek(to: $0) }),
                   in: 0...max(engine.duration, 1))
                .tint(.white)

            HStack {
                Text(formatTime(engine.currentTime)).font(.caption).foregroundStyle(.white.opacity(0.7))
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

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - LRC 解析（本文件内私有）

struct LRCLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

private func parseLRC(_ raw: String) -> [LRCLine] {
    var lines: [LRCLine] = []
    guard let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]") else { return lines }
    for rawLine in raw.components(separatedBy: .newlines) {
        let ns = rawLine as NSString
        let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { continue }
        let last = matches.last!
        let text = ns.substring(from: last.range.location + last.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        for m in matches {
            let minute = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let second = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let msRange = m.range(at: 3)
            var frac = 0.0
            if msRange.location != NSNotFound {
                let msStr = ns.substring(with: msRange)
                let ms = Int(msStr) ?? 0
                frac = msStr.count >= 3 ? Double(ms) / 1000.0 : Double(ms) / 100.0
            }
            let time = Double(minute * 60 + second) + frac
            lines.append(LRCLine(time: time, text: text))
        }
    }
    return lines.sorted { $0.time < $1.time }
}
