import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// ============================================================================
// 全局皮肤 v3 — 混合渲染架构。
// 前两轮失败的根因都是"拿 SwiftUI 半透明层当全屏壁纸":
//   · overlay 挂法: List/ScrollView 逐行异步合成, 每行都要重过一遍模糊层 → 卡死、控件失灵
//   · background 挂法: 系统列表自带不透明背景, 把底下的皮肤层整个盖掉 → "看不见效果"
// v3: 壁纸位交给 UIKit —— 在 keyWindow 最底层插一个 UIImageView(一次性位图, 运行期零开销);
//     上层给 List 铺 material 让文字可读; blur/dim 预烘焙进位图, 不在渲染循环里算。
// ============================================================================

enum SkinBackdrop {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static var cache: [String: UIImage] = [:]

    /// 把原图烘焙成"降采样+高斯模糊+压暗"的成品壁纸, 同参数只算一次
    static func backdrop(for image: UIImage, blur: Double, dim: Double) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let key = "\(cg.width)x\(cg.height)|\(Int(blur))|\(Int(dim * 100))"
        if let hit = cache[key] { return hit }

        // 1) 降采样到 ~1200px(屏幕量级), CGContext 缩放线程安全
        let pxW = CGFloat(cg.width), pxH = CGFloat(cg.height)
        let factor = min(1, 1200 / max(pxW, pxH))
        let w = max(1, Int(pxW * factor)), h = max(1, Int(pxH * factor))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }

        // 2) CoreImage 高斯模糊(半径按缩放比例折) + 亮度压制
        var out = CIImage(cgImage: small)
        if blur > 0.5 {
            out = out.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur * Double(factor)])
                .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        }
        out = out.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: -dim * 0.45,
            kCIInputContrastKey: 1.0 + dim * 0.2,
        ])
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        guard let blurred = ciContext.createCGImage(out, from: extent) else { return UIImage(cgImage: small) }

        // 3) 黑遮罩直接烘进位图(保证白字可读), 运行期不再叠层
        guard let finalCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return UIImage(cgImage: blurred) }
        finalCtx.draw(blurred, in: extent)
        finalCtx.setFillColor(UIColor.black.withAlphaComponent(CGFloat(dim) * 0.55).cgColor)
        finalCtx.fill(extent)
        guard let final = finalCtx.makeImage() else { return UIImage(cgImage: blurred) }

        let result = UIImage(cgImage: final)
        if cache.count > 6 { cache.removeAll() }   // 防滑杆连拖撑爆内存
        cache[key] = result
        return result
    }
}

/// 往 keyWindow 最底层插壁纸 UIImageView; image=nil 时移除。
@MainActor
final class SkinWallpaperHost {
    static let shared = SkinWallpaperHost()
    weak var imageView: UIImageView?

    private init() {}

    func apply(_ image: UIImage?) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        if let image {
            let iv: UIImageView
            if let existing = imageView, existing.window === window {
                iv = existing
            } else {
                iv = UIImageView(frame: window.bounds)
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                iv.isUserInteractionEnabled = false
                window.insertSubview(iv, at: 0)
                imageView = iv
            }
            iv.image = image
        } else {
            imageView?.removeFromSuperview()
            imageView = nil
        }
    }
}

/// SwiftUI 侧胶水视图: 挂在 ContentView 的 .background 位。
/// 自身只画一层极淡黑色蒙版(List 会因背景存在而转透明), 真正的壁纸由 Host 塞窗口底层。
struct SkinGlobalOverlay: View {
    @ObservedObject private var skin = SkinManager.shared

    var body: some View {
        ZStack {
            if skin.globalEnabled, skin.enabled, let img = skin.backdropImage ?? skin.image {
                // 占位不透明层: 逼 SwiftUI List 走"有背景"分支, 同时轻微压色增强可读性
                Color.black.opacity(0.001)
                    .onAppear { bakeAndApply(img) }
                    .onChange(of: bakeToken) { _ in
                        if let src = skin.backdropImage ?? skin.image { bakeAndApply(src) }
                    }
            }
        }
        .ignoresSafeArea()
    }

    private var bakeToken: String {
        "\(skin.globalEnabled)-\(skin.enabled)-\(Int(skin.globalBlur))-\(Int(skin.globalDim * 100))"
    }

    private func bakeAndApply(_ src: UIImage) {
        let blur = skin.globalBlur, dim = skin.globalDim
        guard skin.globalEnabled, skin.enabled else {
            SkinWallpaperHost.shared.apply(nil)
            return
        }
        // 烘焙放后台, 完成回主线程贴窗口 —— 滑杆拖动不卡 UI
        DispatchQueue.global(qos: .userInitiated).async {
            let baked = SkinBackdrop.backdrop(for: src, blur: blur, dim: dim)
            DispatchQueue.main.async {
                SkinWallpaperHost.shared.apply(baked)
            }
        }
    }
}
