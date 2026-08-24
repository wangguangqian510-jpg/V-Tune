import SwiftUI

// ============================================================================
// SkinOverlay — 全局皮肤层: 挂在 App 根(WindowGroup)覆盖所有页面。
// 播放页自带背景层(可单独调参), 这里负责其余一切页面(曲库/设置/歌单…)。
// 用 UIGestureRecognizerRepresentable 挂 backdrop 下方, 列表滚动/点击不受影响。
// ============================================================================

struct SkinGlobalBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = PassthroughUIView()
        v.isUserInteractionEnabled = false
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// 默认 hitTest 返回 nil → 整层对触摸透明, 下面的内容照常交互
    final class PassthroughUIView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}

struct SkinGlobalOverlay: View {
    @ObservedObject private var skin = SkinManager.shared

    var body: some View {
        // 指针事件完全穿透(SwiftUI 层), 真正的视觉内容由 UIKit 层渲染
        skinLayer
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var skinLayer: some View {
        if skin.globalEnabled, skin.enabled, let img = skin.image {
            GeometryReader { geo in
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: skin.globalBlur)
                    .overlay(Color.black.opacity(skin.globalDim))
            }
        } else {
            EmptyView()
        }
    }
}
