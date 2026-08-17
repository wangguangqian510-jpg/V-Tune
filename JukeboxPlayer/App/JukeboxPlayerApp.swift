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
        .onAppear {
            engine.load(store.tracks)
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
                store.noteImport(url.lastPathComponent, ok: true, message: "onOpenURL 触发：\(url.absoluteString)")
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
