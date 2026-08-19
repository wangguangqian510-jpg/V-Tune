import SwiftUI

@main
struct JukeboxPlayerApp: App {
    @StateObject private var engine = PlayerEngine()
    @StateObject private var store = TrackStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(store)
                // 全局背景挂到 UIWindow 最底层，所有页面统一透出来。
                .overlay(WindowBackground())
        .onAppear {
            engine.load(store.tracks)
            // 预触发 iOS 网络权限弹窗：避免用户第一次点远程示例曲时才被打断。
            // 使用 HEAD 请求，不下载正文；失败不影响本地播放。
            if let url = URL(string: "https://www.baidu.com") {
                var req = URLRequest(url: url)
                req.httpMethod = "HEAD"
                req.timeoutInterval = 5
                URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
            }
        }
        .onChange(of: store.catalogVersion) { _ in
            engine.load(store.tracks)
        }
        // 修复：接收从 iOS「文件」App 通过「分享 / 打开」送进来的本地音频。
        // 之前没有 onOpenURL，系统虽能把文件调起 App（Info.plist 已注册音频类型），
        // 但 App 内部没接住，文件被丢弃 -> 表现为「本地 mp3 导不进」。
        // 注意：Release 构建下 #if DEBUG 的 print 会被裁掉，所以失败必须走 UI 提示，
        // 否则会静默吞错、表现为「分享后进 App 主页无事发生」。
        .onOpenURL { url in
            Task { @MainActor in
                let ext = url.pathExtension.lowercased()
                store.noteImport(url.lastPathComponent, ok: true, message: "onOpenURL 触发：\(url.absoluteString)")
                // 歌词文件（.lrc/.txt）分享进 App：绑定到当前曲目，而不是当媒体导入成坏曲目。
                if ["lrc", "txt"].contains(ext) {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        store.reportImportResult("歌词文件读取失败：\(url.lastPathComponent)")
                        return
                    }
                    if engine.tracks.indices.contains(engine.currentIndex) {
                        engine.setLyricsForCurrent(text)
                        store.reportImportResult("已为当前歌曲绑定歌词：\(url.lastPathComponent)")
                    } else {
                        store.reportImportResult("没有正在播放的歌曲，无法绑定歌词（请先播放一首再分享 .lrc）")
                    }
                    return
                }
                do {
                    try await store.importFile(from: url)
                } catch {
                    store.reportImportResult("分享导入失败：\(error.localizedDescription)")
                }
            }
        }
        }
    }
}
