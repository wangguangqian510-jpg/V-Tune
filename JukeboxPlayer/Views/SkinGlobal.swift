import SwiftUI
import UIKit

// ============================================================================
// SkinGlobalOverlay — 全局皮肤层: 挂在 App 根覆盖所有页面(曲库/设置/歌单…)。
// 性能铁律: 背景图一律用降采样后的 backdropImage; 先铺满再 blur+drawingGroup 烘焙成单张贴图;
// 绝不套 GeometryReader——它会向上传播尺寸提案, 在 NavigationStack 根部 .overlay 里引发布局反馈循环。
// ============================================================================

struct SkinGlobalOverlay: View {
    @ObservedObject private var skin = SkinManager.shared

    var body: some View {
        if skin.globalEnabled, skin.enabled, let img = skin.backdropImage ?? skin.image {
            // 顺序关键: scaledToFill 铺满屏幕后再 blur → drawingGroup 烘焙。
            // 若先对未受限尺寸的源图做模糊, Metal 会按原图尺寸建离屏缓冲(4608×3456 就是 60MB+),
            // 每帧重建 → 主线程卡死、全 app 控件失灵(上版卡屏根因)。
            Image(uiImage: img)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .blur(radius: skin.globalBlur)
                .overlay(Color.black.opacity(skin.globalDim))
                .drawingGroup()   // 合成一张位图贴图, 滚动时只贴不重算
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
