import SwiftUI
import UIKit

/// 把背景图挂到 App 的 UIWindow 最底层，绕过 SwiftUI NavigationStack / List / Form 的系统背景遮挡。
/// 这样自定义图片或专辑封面能在主页、曲库、歌手/专辑/歌单、设置页、播放页统一透出来。
struct WindowBackground: UIViewRepresentable {
    @EnvironmentObject var store: TrackStore
    @EnvironmentObject var engine: PlayerEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        updateWindows()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updateWindows()
    }

    private func updateWindows() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        for window in scene.windows {
            // 移除旧背景（避免叠加多层）
            window.viewWithTag(98765)?.removeFromSuperview()

            let container = UIView(frame: window.bounds)
            container.tag = 98765
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.backgroundColor = .clear

            let dimOpacity: Double
            if store.backgroundModeEnum == .custom, let img = store.loadCustomBackground() {
                let iv = UIImageView(frame: container.bounds)
                iv.image = img
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(iv)
                dimOpacity = 1 - store.customBackgroundOpacity
            } else if let img = engine.artwork {
                let iv = UIImageView(frame: container.bounds)
                iv.image = img
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(iv)
                dimOpacity = 0.5
            } else {
                // 无封面时：用当前主题色到黑色的渐变兜底
                let gradient = CAGradientLayer()
                gradient.frame = container.bounds
                gradient.colors = (engine.currentCover + [.black]).map { UIColor($0).cgColor }
                gradient.startPoint = CGPoint(x: 0, y: 0)
                gradient.endPoint = CGPoint(x: 0, y: 1)
                container.layer.addSublayer(gradient)
                dimOpacity = 0.0
            }

            // 黑色遮罩控制浓度（自定义模式下 0~1 对应浓度 Slider）
            if dimOpacity > 0 {
                let overlay = UIView(frame: container.bounds)
                overlay.backgroundColor = UIColor.black.withAlphaComponent(dimOpacity)
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(overlay)
            }

            window.insertSubview(container, at: 0)
        }
    }
}
