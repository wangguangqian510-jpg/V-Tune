import SwiftUI

import PhotosUI

/// 纯 String 常量：避免 SWIFT_EMIT_LOC_STRINGS 把 Section/Text 标题抽进本地化目录导致二进制里缺失。
private let skinSectionTitle = "个性化皮肤"



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

    @State private var showPhotoPicker = false



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
                HStack { Text("导入模式"); Spacer(); Text("复制到 App（强制）").foregroundStyle(.secondary) }
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


                HStack { Text("网络音频"); Spacer(); Text("\(storage.remoteCount)") }

                HStack { Text("我的收藏"); Spacer(); Text("\(storage.favoriteCount)") }

                HStack { Text("歌单"); Spacer(); Text("\(storage.playlistCount)") }

            }

            Section("关于") {

                HStack { Text("版本"); Spacer(); Text(appVersion) }

                HStack { Text("Bundle ID"); Spacer(); Text(Bundle.main.bundleIdentifier ?? "") }

            }

            Section("导入诊断") {

                Toggle("记录导入诊断日志", isOn: $store.importDiagnosticsEnabled)

                if store.importDiagnosticsEnabled {

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

                        Text("2. 导入强制「复制进 App」：重签名/轻松签环境最稳可靠（原始文件可保留在 Files 自行管理）")

                        Text("3. 歌词：播放页点「歌词」→「在线搜」，按歌名/歌手自动拉取")

                        Text("4. 文件 App 分享：长按音频/视频文件 → 共享 → 选 乐影")

                    }

                    .font(.caption)

                    .foregroundStyle(.secondary)

                } else {

                    Text("开启后才会记录每次导入的触发/成功/失败详情，并显示导入记录。日常导入建议关闭以减少打扰。")

                        .font(.caption)

                        .foregroundStyle(.secondary)

                }

            }



            Section {
                Text(verbatim: skinSectionTitle)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("主题色")
                    HStack(spacing: 14) {
                        ForEach(AccentColor.allCases) { c in
                            Circle()
                                .fill(c.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(store.accentColorName == c.rawValue ? Color.white : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture { store.accentColorName = c.rawValue }
                        }
                    }
                }
                Text("主题色会同步到播放页的按钮与进度条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("背景", selection: $store.backgroundMode) {
                    ForEach(BackgroundMode.allCases) { m in
                        Text(m.displayName).tag(m.rawValue)
                    }
                }
                if store.backgroundModeEnum == .custom {
                    Button { showPhotoPicker = true } label: {
                        Label("选择背景图片", systemImage: "photo")
                    }
                    if store.loadCustomBackground() != nil {
                        Button(role: .destructive) {
                            store.clearCustomBackground()
                        } label: {
                            Label("清除背景图片", systemImage: "trash")
                        }
                    }
                }
                Text("自定义背景图会复制到 App 沙盒（与导入音频一致，卸载即删除）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }


            if store.importDiagnosticsEnabled {

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

        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(onPick: { img in
                if store.setCustomBackground(img) {
                    store.backgroundMode = BackgroundMode.custom.rawValue
                }
            })
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

/// 从系统相册选择一张图片作为播放页背景（PHPicker，iOS 14+，无需相册授权）。
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.parent.onPick(image) }
                }
            }
        }
    }
}

