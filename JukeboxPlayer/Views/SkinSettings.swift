import PhotosUI
import SwiftUI

// ============================================================================
// SkinManager — 自定义皮肤: 用自己的图片当播放页背景
// 图片存 Documents/skin_background.jpg(压缩), 参数存 UserDefaults。单例, 播放页直接读。
// ============================================================================

final class SkinManager: ObservableObject {
    static let shared = SkinManager()

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "SkinEnabled_v1") } }
    /// 背景模糊半径 0-20
    @Published var blur: Double { didSet { UserDefaults.standard.set(blur, forKey: "SkinBlur_v1") } }
    /// 暗色遮罩 0-0.8 (保证白色控件可读)
    @Published var dim: Double { didSet { UserDefaults.standard.set(dim, forKey: "SkinDim_v1") } }
    /// 黑胶衬底: 仅在未开启纯皮肤模式时生效。开=皮肤图上仍显示黑胶转盘; 关=封面卡片浮在背景上
    @Published var vinylBackdrop: Bool { didSet { UserDefaults.standard.set(vinylBackdrop, forKey: "SkinVinyl_v1") } }
    /// 纯皮肤模式: 隐藏黑胶圆盘, 封面卡片直接浮在皮肤图上(竖屏观感更干净)。默认开。
    @Published var pureMode: Bool { didSet { UserDefaults.standard.set(pureMode, forKey: "SkinPure_v1") } }
    /// 全局皮肤: 开=皮肤图覆盖所有页面(曲库/设置/歌单…); 播放页始终用自己的背景层
    @Published var globalEnabled: Bool { didSet { UserDefaults.standard.set(globalEnabled, forKey: "SkinGlobal_v1") } }
    /// 全局页参数单独一组: 列表页要保证文字可读, 默认比播放页更模糊更暗
    @Published var globalBlur: Double { didSet { UserDefaults.standard.set(globalBlur, forKey: "SkinGBlur_v1") } }
    @Published var globalDim: Double { didSet { UserDefaults.standard.set(globalDim, forKey: "SkinGDim_v1") } }
    @Published private(set) var image: UIImage?
    /// 降采样后的背景专用小图(最长边 900): 专供两页背景渲染用。
    /// 直接拿原尺寸大图铺满+模糊, 每帧都要缩放整张位图 → 全局卡屏、控件失灵(上版 bug 根源)。
    /// 注意: 必须是独立存储的字段, 不能是计算属性——否则每次 body 求值都重新缩放一次。
    @Published private(set) var backdropImage: UIImage?

    private var skinURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("skin_background.jpg")
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "SkinEnabled_v1")
        blur = UserDefaults.standard.object(forKey: "SkinBlur_v1") as? Double ?? 6
        dim = UserDefaults.standard.object(forKey: "SkinDim_v1") as? Double ?? 0.45
        vinylBackdrop = UserDefaults.standard.object(forKey: "SkinVinyl_v1") as? Bool ?? true
        pureMode = UserDefaults.standard.object(forKey: "SkinPure_v1") as? Bool ?? true
        globalEnabled = UserDefaults.standard.bool(forKey: "SkinGlobal_v1")
        globalBlur = UserDefaults.standard.object(forKey: "SkinGBlur_v1") as? Double ?? 14
        globalDim = UserDefaults.standard.object(forKey: "SkinGDim_v1") as? Double ?? 0.72
        if let data = try? Data(contentsOf: skinURL), let img = UIImage(data: data) {
            image = img
            backdropImage = Self.downsample(img, maxSide: 900)
        } else {
            enabled = false
        }
    }

    /// 位图降采样: ImageIO 按目标尺寸解码, 内存与渲染开销大幅低于先解全图再缩
    static func downsample(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longest > maxSide else { return image }
        let factor = maxSide / longest
        guard let cg = image.cgImage else { return image }
        let newW = max(1, Int(cg.width * factor))
        let newH = max(1, Int(cg.height * factor))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: newW, height: newH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let out = ctx.makeImage() else { return image }
        return UIImage(cgImage: out, scale: 1, orientation: image.imageOrientation)
    }

    func save(_ uiImage: UIImage) {
        // 压到最长边 1600 再存, 控制内存与磁盘
        let maxSide: CGFloat = 1600
        var target = uiImage
        let longest = max(uiImage.size.width, uiImage.size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        guard let data = target.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: skinURL, options: [.atomic])
            image = target
            backdropImage = Self.downsample(target, maxSide: 900)
            enabled = true
        } catch {
            // 存盘失败保持旧状态
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: skinURL)
        image = nil
        backdropImage = nil
        enabled = false
    }
}

// MARK: - PHPicker 封装

struct SkinPhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SkinPhotoPicker
        init(_ parent: SkinPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let img = obj as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.parent.onPick(img)
                }
            }
        }

        func pickerDidCancel(_ picker: PHPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - 皮肤设置页

struct SkinSettingsView: View {
    @ObservedObject private var skin = SkinManager.shared
    @State private var showingPicker = false

    var body: some View {
        List {
            Section("背景图") {
                if let img = skin.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    showingPicker = true
                } label: {
                    Label(skin.image == nil ? "从相册选择图片" : "更换图片", systemImage: "photo")
                }
                Toggle("使用自定义背景", isOn: $skin.enabled)
                    .disabled(skin.image == nil)
                Toggle("纯皮肤模式(隐藏黑胶圆盘)", isOn: $skin.pureMode)
                    .disabled(!skin.enabled)
                if skin.enabled && !skin.pureMode {
                    Toggle("黑胶衬底", isOn: $skin.vinylBackdrop)
                }
                Toggle("应用到全局(曲库/设置等所有页面)", isOn: $skin.globalEnabled)
                    .disabled(!skin.enabled)
                if skin.globalEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("全局模糊"); Spacer(); Text("\(Int(skin.globalBlur))").foregroundStyle(.secondary) }
                        Slider(value: $skin.globalBlur, in: 0...30, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("全局暗度"); Spacer(); Text("\(Int(skin.globalDim * 100))%").foregroundStyle(.secondary) }
                        Slider(value: $skin.globalDim, in: 0.3...0.92, step: 0.02)
                    }
                }
                if skin.image != nil {
                    Button(role: .destructive) {
                        skin.clear()
                    } label: {
                        Label("删除背景图", systemImage: "trash")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("模糊强度"); Spacer(); Text("\(Int(skin.blur))").foregroundStyle(.secondary) }
                    Slider(value: $skin.blur, in: 0...20, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("暗度"); Spacer(); Text("\(Int(skin.dim * 100))%").foregroundStyle(.secondary) }
                    Slider(value: $skin.dim, in: 0...0.8, step: 0.05)
                }
                Text("提示: 稍微加一点模糊和暗度, 播放页的白色文字会更清楚")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("效果调节")
            } footer: {
                Text("黑胶衬底开: 皮肤图上保留转盘; 关: 纯皮肤模式, 封面卡片浮在背景上。生效范围: 播放页。")
            }
        }
        .navigationTitle("自定义皮肤")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            SkinPhotoPicker(isPresented: $showingPicker) { img in skin.save(img) }
        }
    }
}
