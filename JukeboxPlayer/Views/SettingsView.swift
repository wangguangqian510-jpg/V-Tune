import SwiftUI

/// 设置页展示的存储与曲库概况。
struct StorageInfo {
    var docsBytes: Int64 = 0
    var cacheBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var importedFiles: Int = 0
    var remoteCount: Int = 0
    var totalTracks: Int = 0
    var favoriteCount: Int = 0
    var playlistCount: Int = 0
}

func formatBytes(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: value)
}

struct SettingsView: View {
    @EnvironmentObject private var store: TrackStore
    @EnvironmentObject private var engine: PlayerEngine

    @State private var storage: StorageInfo = StorageInfo()
    @State private var showingClearConfirm = false
    @State private var showingCleared = false
    @State private var clearResult: String?

    var body: some View {
        List {
            Section("占用空间") {
                HStack { Text("文档（导入音频）"); Spacer(); Text(formatBytes(storage.docsBytes)) }
                HStack { Text("缓存"); Spacer(); Text(formatBytes(storage.cacheBytes)) }
                HStack { Text("合计"); Spacer(); Text(formatBytes(storage.totalBytes)).bold() }
                Button(role: .destructive) {
                    showingClearConfirm = true
                } label: {
                    Label("清理缓存（删除本地导入音频）", systemImage: "trash")
                }
                .disabled(storage.importedFiles == 0)
            }
            Section("曲库") {
                HStack { Text("曲目总数"); Spacer(); Text("\(storage.totalTracks)") }
                HStack { Text("本地文件"); Spacer(); Text("\(storage.importedFiles)") }
                HStack { Text("网络音频"); Spacer(); Text("\(storage.remoteCount)") }
                HStack { Text("我的收藏"); Spacer(); Text("\(storage.favoriteCount)") }
                HStack { Text("歌单"); Spacer(); Text("\(storage.playlistCount)") }
            }
            Section("关于") {
                HStack { Text("版本"); Spacer(); Text(appVersion) }
                HStack { Text("构建"); Spacer(); Text(appBuild) }
                HStack { Text("Bundle ID"); Spacer(); Text(Bundle.main.bundleIdentifier ?? "") }
            }
        }
        .navigationTitle("设置")
        .onAppear { storage = store.storageInfo() }
        .alert("确认清理缓存", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                let freed = store.clearLocalCache()
                storage = store.storageInfo()
                clearResult = "已释放 \(formatBytes(freed))，本地导入音频已删除"
                showingCleared = true
            }
        } message: {
            Text("将删除本机导入的所有本地音频文件以释放空间，网络音频链接不受影响。此操作不可撤销。")
        }
        .alert("清理完成", isPresented: $showingCleared) {
            Button("确定", role: .cancel) { clearResult = nil }
        } message: {
            Text(clearResult ?? "")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// 每次提交新构建时手动更新，便于在反馈时确认装的是哪个版本。
    private var appBuild: String { "2026-08-17 #32" }
}
