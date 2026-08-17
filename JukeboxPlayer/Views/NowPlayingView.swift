import SwiftUI

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
                Spacer(minLength: 0)
                queueToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .foregroundStyle(.white)

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

    // MARK: Artwork
    private var artwork: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(LinearGradient(colors: engine.currentCover,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .shadow(radius: 20, y: 10)
            .overlay {
                if let img = engine.artwork {
                    Image(uiImage: img).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
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
                    get: { engine.isScrubbing ? scrubTime : engine.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(engine.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        // 开始拖动：冻结进度显示，停止对播放器的连续 seek
                        engine.isScrubbing = true
                        scrubTime = engine.currentTime
                    } else {
                        // 松手：一次性精确跳转到目标位置，恢复正常进度跟踪
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
        ZStack(alignment: .topTrailing) {
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
                ScrollView {
                    if let lyrics = engine.lyrics, !lyrics.isEmpty {
                        Text(lyrics)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                    } else {
                        Text("暂无歌词")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
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
