//
//  DesignSystem.swift
//  FreeGrid
//
//  方向 v3: Silverline · Swiss-tech Light Minimal
//  - 冷白底 + 雾银低饱和(蓝灰 hue)
//  - 唯一 accent = 天空蓝 (sky blue)
//  - hairline 描边 + 大量留白替代色块填充
//  - SF Pro Rounded thin 大数字,克制不发光
//
//  与 v2 暗色金库的对应:colors 翻转(dark→light), 但 layout 结构(VaultCard 堆叠)保留
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - Dynamic color helper
// ============================================================================
// SwiftUI Color 没有原生 light/dark 双值 init,用 UIColor.dynamicProvider 桥接。
// 切换 .preferredColorScheme(.light/.dark) 时所有 dynamic color 自动 resolve。

extension Color {
    /// 创建一个根据 colorScheme 自动切换的 Color
    static func dyn(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }

    /// 直接用 RGB 三元组创建 dynamic (避免嵌套 Color)
    static func dyn(
        lightRGB: (Double, Double, Double),
        darkRGB: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkRGB : lightRGB
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }
}

// ============================================================================
// MARK: - Color tokens (light silverline / dark vault dual mode)
// ============================================================================

extension Color {

    // ===== Surface (液态玻璃: 淡绿灰底 + 玻璃浮起卡 — 念念有账 UI v2) =====
    /// 主底
    static let paper = Color.dyn(
        lightRGB: (0.875, 0.906, 0.882),   // #dfe7e1 淡绿灰
        darkRGB:  (0.027, 0.039, 0.031)    // #070a08 近黑绿
    )
    /// 卡片底(玻璃卡不可用时兑底)
    static let mist = Color.dyn(
        lightRGB: (0.998, 0.999, 1.000),
        darkRGB:  (0.094, 0.125, 0.106)    // #18201b 绿黑
    )
    /// 嵌套深一档
    static let mist2 = Color.dyn(
        lightRGB: (0.906, 0.933, 0.914),
        darkRGB:  (0.130, 0.170, 0.145)
    )
    /// hairline 主分隔
    static let hairline = Color.dyn(
        lightRGB: (0.800, 0.850, 0.815),
        darkRGB:  (0.180, 0.230, 0.200)
    )
    /// hairline 次级
    static let hairlineSoft = Color.dyn(
        lightRGB: (0.870, 0.900, 0.880),
        darkRGB:  (0.140, 0.180, 0.158)
    )

    // ===== Ink scale (light: 深绿墨 / dark: 绿白系) =====
    /// 主文字
    static let ink = Color.dyn(
        lightRGB: (0.059, 0.082, 0.071),   // #0f1512
        darkRGB:  (0.941, 0.961, 0.945)    // #f0f5f1
    )
    /// 次级文字 (--sub)
    static let inkMuted = Color.dyn(
        lightRGB: (0.408, 0.459, 0.427),   // #68756d
        darkRGB:  (0.561, 0.627, 0.588)    // #8fa096
    )
    /// 灰阶 (kicker/unit/caption)
    static let inkFaint = Color.dyn(
        lightRGB: (0.58, 0.575, 0.595),
        darkRGB:  (0.480, 0.495, 0.555)
    )
    /// 极弱
    static let inkGhost = Color.dyn(
        lightRGB: (0.74, 0.735, 0.755),
        darkRGB:  (0.310, 0.325, 0.380)
    )

    // ===== Brand green (念念有账主色,原天空蓝 accent 全线转绿) =====
    /// 主天空蓝 → 品牌绿亮端
    static let sky = Color.dyn(
        lightRGB: (0.098, 0.764, 0.490),   // #19c37d 渐变亮端
        darkRGB:  (0.192, 0.831, 0.573)    // #31d492
    )
    /// 深天空蓝 → 品牌绿深端 (强调字/保存按钮/进度条全线变绿)
    static let skyDeep = Color.dyn(
        lightRGB: (0.039, 0.561, 0.345),   // #0a8f58
        darkRGB:  (0.122, 0.702, 0.455)    // #1fb374
    )
    /// 浅 sky soft → 浅绿
    static let skySoft = Color.dyn(
        lightRGB: (0.494, 0.902, 0.714),   // #7ee6b6 blob 绿
        darkRGB:  (0.100, 0.290, 0.200)
    )
    /// 极淡 sky wash → 极淡绿 (banner 底)
    static let skyFaint = Color.dyn(
        lightRGB: (0.898, 0.953, 0.922),
        darkRGB:  (0.075, 0.150, 0.110)
    )
    /// 品牌绿主值 (#0fa968)
    static let brandGreen = Color.dyn(
        lightRGB: (0.059, 0.663, 0.408),
        darkRGB:  (0.098, 0.764, 0.490)
    )

    // ===== 业务语义色 (对齐设计稿 tint) =====
    /// 资产桶蓝 #4f8ef7
    static let assetBlue = Color.dyn(
        lightRGB: (0.310, 0.557, 0.969),
        darkRGB:  (0.400, 0.630, 1.000)
    )
    /// 暖金 #e8a23d
    static let incomeGold = Color.dyn(
        lightRGB: (0.910, 0.635, 0.239),
        darkRGB:  (0.960, 0.720, 0.360)
    )
    /// 支出红 #f0544f
    static let flame = Color.dyn(
        lightRGB: (0.941, 0.329, 0.310),
        darkRGB:  (1.000, 0.420, 0.400)
    )
    /// 收入绿 #17b26a
    static let mossGreen = Color.dyn(
        lightRGB: (0.090, 0.698, 0.416),
        darkRGB:  (0.192, 0.831, 0.573)
    )

    /// 高强调卡填充(VaultCard .high)。light: 纯白(跟普通卡一致, 避免反转后高强调卡变灰);
    /// dark: 维持原 paper 暗值, 暗色高强调卡观感不变。
    static let surfaceHi = Color.dyn(
        lightRGB: (0.998, 0.999, 1.000),
        darkRGB:  (0.040, 0.045, 0.075)
    )

    // ===== V1/V2 alias =====
    static let midnight   = Color.paper
    static let surface    = Color.mist
    static let honey      = Color.ink
    static let honeyDim   = Color.inkMuted
    static let ink2       = Color.inkMuted
    static let ink3       = Color.inkFaint
    static let vermillion = Color.flame
    static let forestGreen = Color.mossGreen
    static let rule       = Color.hairline
    static let ruleSoft   = Color.hairlineSoft
    static let paper2     = Color.mist
}

// ============================================================================
// MARK: - 字体 helper
// ============================================================================
// 用 SF Pro Rounded thin 取代 v3 mockup 的 Geist——iOS 没有 Geist,
// SF Pro 是 system font,weight 100 ultraLight 视觉接近 Geist 100。
// 中文自动 fallback PingFang SC,thin 字重映射合理。

extension Font {
    /// Hero 自由天数:96pt rounded ultraLight,跟 mockup Geist 100 视觉等价
    static func heroNumber(_ size: CGFloat = 96) -> Font {
        .system(size: size, weight: .ultraLight, design: .rounded).monospacedDigit()
    }

    /// 中等数字:stats 用,32pt thin
    static func bigNumber(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    /// 三联指标内部数字
    static func statNumber(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    /// kicker / label:mono uppercase tracking
    static let kicker = Font.system(.caption2, design: .monospaced).weight(.regular)

    /// 副标 body rounded
    static let bodyRounded = Font.system(.body, design: .rounded)

    // ===== V1/V2 alias =====
    static func mediumNumber(_ size: CGFloat = 28) -> Font { bigNumber(size) }
    static let monoKicker = kicker
}

// ============================================================================
// MARK: - 共用组件
// ============================================================================

/// kicker 标签:uppercase mono tracking,默认 inkFaint
struct KickerLabel: View {
    let text: String
    var color: Color = .inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(.kicker)
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

/// hairline 横线
struct Hairline: View {
    var color: Color = .hairline
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// 卡片容器:Silverline 风
/// emphasis = .high 用 paper 纯白(更亮一档);.normal 用 mist 雾银
/// 设计动机:hairline 描边为主,无阴影,极简
struct VaultCard<Content: View>: View {
    enum Emphasis { case normal, high }
    var emphasis: Emphasis = .normal
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)          // 液态玻璃: blur(22px)+saturate 等效
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.094, green: 0.227, blue: 0.157).opacity(0.12),
                    radius: 15, y: 10)
    }
}

/// 液态玻璃页面背景: 主底色 + 三枚彩色光斑 (blur 70 / 深色降透明度)
struct GlassBlobs: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color.paper
            GeometryReader { geo in
                let op: Double = scheme == .dark ? 0.22 : 0.50
                blob(Color(red: 0.494, green: 0.902, blue: 0.714),   // #7ee6b6 绿
                     size: geo.size.width * 0.85,
                     x: -geo.size.width * 0.22, y: -geo.size.height * 0.14,
                     opacity: op)
                blob(Color(red: 1.000, green: 0.851, blue: 0.541),   // #ffd98a 暖黄
                     size: geo.size.width * 0.75,
                     x: geo.size.width * 0.82, y: geo.size.height * 0.32,
                     opacity: op)
                blob(Color(red: 0.620, green: 0.796, blue: 1.000),   // #9ecbff 蓝
                     size: geo.size.width * 0.82,
                     x: geo.size.width * 0.16, y: geo.size.height * 0.88,
                     opacity: op)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 70)
            .opacity(opacity)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }
}

/// 主操作按钮 — hairline 描边 pill 风
/// .primary = 实心 ink 底 paper 字
/// .secondary = 透明 + ink 描边
/// .destructive = 透明 + flame 描边 + flame 字
struct VaultButton: View {
    enum Style { case primary, secondary, destructive }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    private var bg: Color {
        // 所有 style 都不填色,统一 outline 风
        return .clear
    }
    private var fg: Color {
        switch style {
        case .primary: return .skyDeep   // 深天空蓝字 (跟 flame destructive 对称)
        case .secondary: return .ink
        case .destructive: return .flame
        }
    }
    private var stroke: Color {
        switch style {
        case .primary: return .skyDeep   // 深天空蓝描边
        case .secondary: return .ink
        case .destructive: return .flame
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(fg)
            .background(
                Capsule().fill(bg)
            )
            .overlay(
                Capsule().stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Ghost 按钮:underline 文字 link 风
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .regular))
                }
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.inkFaint)
            .overlay(
                Rectangle()
                    .fill(Color.hairlineSoft)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .bottom),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
// MARK: - V1 组件 alias (年鉴风 + 暗色金库时期遗留)
// ============================================================================

struct SectionMark: View {
    let text: String
    var color: Color = .inkFaint
    var body: some View {
        KickerLabel(text: text, color: color)
    }
}

struct ChapterRule: View {
    var body: some View { Hairline() }
}

struct PillButton: View {
    enum Emphasis { case primary, secondary }
    let title: String
    var icon: String? = nil
    var emphasis: Emphasis = .secondary
    var tint: Color = .ink
    let action: () -> Void

    var body: some View {
        let style: VaultButton.Style = (tint == .flame || tint == .vermillion) ? .destructive : .primary
        VaultButton(title: title, icon: icon, style: style, action: action)
    }
}

struct UnderlineLink: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        GhostButton(title: title, icon: icon, action: action)
    }
}

/// emphasized():单字 italic 强调
/// light silverline 版本:用 sky-deep 深天空蓝代替 honey/vermillion
/// 配合 .italic 用类衬线感强调(SF 没 italic serif,但 .italic() + tracking 微调可以)
func emphasized(_ prefix: String, _ word: String, _ suffix: String,
                size: CGFloat = 17) -> Text {
    Text(prefix)
        .font(.system(size: size, weight: .regular, design: .rounded))
        .foregroundColor(.inkMuted)
    + Text(word)
        .font(.system(size: size, weight: .regular, design: .serif).italic())
        .foregroundColor(.skyDeep)
    + Text(suffix)
        .font(.system(size: size, weight: .regular, design: .rounded))
        .foregroundColor(.inkMuted)
}

// ============================================================================
// MARK: - 间距 token
// ============================================================================

enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// ============================================================================
// MARK: - Sparkline (折线图组件)
// ============================================================================
// 设计动机:hero card 底部展示过去 12 周自由天数走势。
// silverline 风:1pt skyDeep stroke,无填充,无 axes,无 grid。
// 最后一个 point 放一个小圆点强调"现在"。

struct Sparkline: View {
    /// y 值数组,index 0 = 最老,index n-1 = 最新
    let values: [Double]
    /// 画线颜色
    var stroke: Color = .skyDeep
    /// 终点圆点颜色
    var endDot: Color = .skyDeep
    /// 线宽
    var lineWidth: CGFloat = 1.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))

            ZStack {
                // 折线
                if pts.count >= 2 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                    .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                // 终点小圆
                if let last = pts.last {
                    Circle()
                        .fill(endDot)
                        .frame(width: 5, height: 5)
                        .position(x: last.x, y: last.y)
                }
            }
        }
    }

    /// 把 values 映射到 view 坐标点
    private func points(in size: CGSize) -> [CGPoint] {
        let safeValues = values
            .filter { $0.isFinite && $0 >= 0 }
            .map { min($0, 365.25 * 99) }
        guard !safeValues.isEmpty else { return [] }
        let minV = safeValues.min() ?? 0
        let maxV = safeValues.max() ?? 1
        let range = max(maxV - minV, 1)   // 避免除零
        let stepX = safeValues.count > 1 ? size.width / CGFloat(safeValues.count - 1) : 0
        let pad: CGFloat = 4              // 上下留 4pt 让线不贴边

        return safeValues.enumerated().map { (i, v) in
            let x = CGFloat(i) * stepX
            let normalized = (v - minV) / range    // 0...1
            let y = size.height - pad - CGFloat(normalized) * (size.height - 2 * pad)
            return CGPoint(x: x, y: y)
        }
    }
}
