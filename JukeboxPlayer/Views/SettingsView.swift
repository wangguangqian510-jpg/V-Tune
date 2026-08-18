import SwiftUI

/// 设置页展示的存储与曲库概况。
struct StorageInfo {
    var docsBytes: Int64 = 0
    var cacheBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var importedFiles: Int = 0
    var referencedCount: Int = 0
    var remoteCount: Int = 0
    var totalTracks: Int = 0
    var favoriteCount: Int = 0
    var playlistCount: Int = 0
    var hiddenSamples: Int = 0
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
            Section("导入设置") {
                Toggle("导入时复制进 App（关 = 引用原文件，省空间）", isOn: $store.importByCopy)
                Text("默认开启复制：导入最稳，重签名/轻松签旁载环境也能正常播放（代价是占 2 倍空间）。关闭后改「引用原文件」省空间，但该模式依赖系统安全书签，在旁载重签名 App 里可能解析失败、导入后播不了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack { Text("引用原文件（不复制）"); Spacer(); Text("\(storage.referencedCount)") }
                HStack { Text("已复制（占 2 倍空间）"); Spacer(); Text("\(storage.importedFiles)") }
                Button {
                    store.restoreSamples()
                    storage = store.storageInfo()
                } label: {
                    Label("恢复被删除的示例曲", systemImage: "arrow.uturn.backward")
                }
                .disabled(storage.hiddenSamples == 0)
            }

            Section("曲库") {
                HStack { Text("曲目总数"); Spacer(); Text("\(storage.totalTracks)") }
                HStack { Text("本地文件（已复制）"); Spacer(); Text("\(storage.importedFiles)") }
                HStack { Text("引用原文件（不复制）"); Spacer(); Text("\(storage.referencedCount)") }
                HStack { Text("网络音频"); Spacer(); Text("\(storage.remoteCount)") }
                HStack { Text("我的收藏"); Spacer(); Text("\(storage.favoriteCount)") }
                HStack { Text("歌单"); Spacer(); Text("\(storage.playlistCount)") }
            }
            Section("关于") {
                HStack { Text("版本"); Spacer(); Text(appVersion) }
                HStack { Text("Bundle ID"); Spacer(); Text(Bundle.main.bundleIdentifier ?? "") }
            }
            Section("导入诊断") {
                Button {
                    store.noteImport("(测试)", ok: true, message: "日志功能正常；若此处有记录而导入后没有，说明导入入口未触发")
                } label: {
                    Label("测试写入一条导入记录", systemImage: "doc.text.magnifyingglass")
                }
                HStack {
                    Text("文档类型注册")
                    Spacer()
                    Text(docTypesRegistered ? "已注册" : "未注册")
                        .foregroundStyle(docTypesRegistered ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("正确导入方式：").bold()
                    Text("1. 应用内：曲库页右上角 + → 从 Files 导入（批量）")
                    Text("2. 默认「复制进 App」：导入最稳，重签名/轻松签环境也能播（占 2 倍空间）。想省空间可在上方开关切到「引用原文件」，但旁载重签名 App 可能解析失败")
                    Text("3. 文件 App：长按 MP3 → 共享/更多 → 选在 Jukebox 中打开或拷贝到 Jukebox（不是顶部分享图标）")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("导入记录") {
                if store.importLog.isEmpty {
                    Text("暂无导入记录（导入一次后会在此显示触发/成功/失败与报错原文）").foregroundStyle(.secondary)
                } else {
                    ForEach(store.importLog) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(entry.ok ? .green : .red)
                                Text(entry.fileName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.time, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
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

    private var docTypesRegistered: Bool {
        (Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])?.isEmpty == false
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
