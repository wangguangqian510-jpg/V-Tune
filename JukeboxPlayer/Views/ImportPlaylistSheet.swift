import SwiftUI
import UniformTypeIdentifiers

/// 导入「歌单 JSON」：支持粘贴文本或选择 .json 文件。
/// 解析逻辑在 TrackStore.importPlaylist(from:) 中（容错多种字段命名）。
struct ImportPlaylistSheet: View {
    @EnvironmentObject private var store: TrackStore
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var showingFilePicker = false
    @State private var message: String?
    @State private var showMessage = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("粘贴歌单 JSON，或选择 .json 文件。\n要求：含曲目数组（tracks / list / songs…），每条带 http(s):// 或 file:// 的 url 字段。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextEditor(text: $jsonText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button { showingFilePicker = true } label: {
                        Label("选择 JSON 文件", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)

                    Button { importText() } label: {
                        Label("导入", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.bottom)
            }
            .navigationTitle("导入歌单 JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.json, .plainText]) { result in
                switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try importData(data)
                    } catch {
                        present(message: error.localizedDescription)
                    }
                case .failure(let error):
                    present(message: error.localizedDescription)
                }
            }
            .alert("导入结果", isPresented: $showMessage) {
                Button("确定", role: .cancel) { dismiss() }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func importText() {
        guard let data = jsonText.data(using: .utf8) else {
            present(message: "文本无法转为 UTF-8"); return
        }
        do { try importData(data) }
        catch { present(message: error.localizedDescription) }
    }

    private func importData(_ data: Data) throws {
        let result = try store.importPlaylist(from: data)
        present(message: "成功导入 \(result.count) 首，已生成歌单「\(result.playlistName)」")
    }

    private func present(message: String) {
        self.message = message
        showMessage = true
    }
}
