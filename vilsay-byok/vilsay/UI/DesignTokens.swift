//
//  DesignTokens.swift
//  vilsay
//
//  统一设计 Token —— 颜色、间距、圆角、卡片、按钮。
//  所有 UI 文件应引用此处定义，避免散落的魔数值。
//

import SwiftUI

// MARK: - 颜色

enum VColor {
    // 背景层级（完全跟随系统深/浅模式）
    static let bgBase     = Color(nsColor: .windowBackgroundColor)
    static let bgCard     = Color(nsColor: .controlBackgroundColor)
    static let bgInput    = Color(nsColor: .textBackgroundColor)

    // 文字层级（完全跟随系统）
    static let textPrimary   = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary  = Color(nsColor: .tertiaryLabelColor)

    // 状态色
    static let ok     = Color.green
    static let warn   = Color.orange
    static let fail   = Color.red
    static let accent = Color.accentColor

    // MARK: 品牌渐变色（橙→粉→紫）
    static let brandOrange = Color(red: 251/255, green: 146/255, blue: 60/255)
    static let brandPink   = Color(red: 244/255, green: 114/255, blue: 182/255)
    static let brandPurple = Color(red: 192/255, green: 132/255, blue: 252/255)
    static let brandIndigo = Color(red: 129/255, green: 140/255, blue: 248/255)

    // 品牌渐变（用于 ShapeStyle）
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandOrange, brandPink, brandPurple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    static var brandGradientVertical: LinearGradient {
        LinearGradient(
            colors: [brandOrange, brandPink, brandPurple],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 浮层专用深色背景
    static let floatBgDeep  = Color(red: 16/255,  green: 9/255,   blue: 4/255)
    static let floatBgCard  = Color(red: 30/255,  green: 21/255,  blue: 16/255)
    // 浮层文字（暖米色，在深色背景上可读）
    static let floatText    = Color(red: 200/255, green: 185/255, blue: 170/255)
    // 浮层 bar 渐变（比 floatBgCard 更深）
    static let floatBarStart = Color(red: 28/255, green: 19/255,  blue: 14/255)
    static let floatBarEnd   = Color(red: 19/255, green: 12/255,  blue: 10/255)
    // 完成 toast 的成功绿（比系统 .green 更鲜明，适合深色浮层）
    static let okVivid = Color(red: 74/255, green: 222/255, blue: 128/255)

    // 第三方品牌色（仅登录按钮使用）
    static let socialWechat = Color(red: 23/255,  green: 186/255, blue: 105/255)

    // MARK: 悬浮按钮专用
    // 在任意桌面壁纸上均清晰可见，深/浅模式均适用
    static let orbIdle       = Color(red: 30/255, green: 21/255, blue: 16/255)   // 深暖棕
    static let orbProcessing = Color(red: 30/255, green: 16/255, blue: 24/255)   // 深紫
    static let orbRecording  = Color(red: 251/255, green: 146/255, blue: 60/255) // 品牌橙
    static let orbEdit       = Color(red: 192/255, green: 132/255, blue: 252/255)// 品牌紫
    static let orbError      = Color.orange
}

// MARK: - 描边宽度

enum VBorder {
    static let hairline: CGFloat = 0.5   // 细描边（chip、卡片内层）
    static let regular:  CGFloat = 1.0   // 标准描边（按钮、输入框）
}

// MARK: - 图标尺寸

enum VIconSize {
    static let xs:   CGFloat = 9    // chip 内删除图标
    static let sm:   CGFloat = 11   // toolbar 小图标
    static let md:   CGFloat = 16   // 行级图标
    static let lg:   CGFloat = 24   // 卡片图标
    static let xl:   CGFloat = 36   // 空状态插图
    static let hero: CGFloat = 48   // 向导页大图标
}

// MARK: - 间距（8pt 基准网格）

enum VSpacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48

    /// 卡片之间的间距
    static let cardGap: CGFloat = 20
    /// 页面外边距
    static let pageInset: CGFloat = 28
}

// MARK: - 圆角

enum VRadius {
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 18
    static let xl:   CGFloat = 24
    static let pill:  CGFloat = 999
}

// MARK: - 卡片 GroupBoxStyle
// 用法：GroupBox("标题") { ... }.groupBoxStyle(VCardStyle())
//
// 参考样式特征：高不透明度磨砂白卡片 / 多层投影 / 大圆角 / 粗标题

struct VCardStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 14)

            configuration.content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
        )
        // 多层阴影：近距 + 远距，让卡片"浮"起来
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.05), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 16, x: 0, y: 6)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if colorScheme == .dark {
            // 深色模式：固定深灰色，不用 material 避免背景渐变导致各卡片颜色不一致
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.92))
        } else {
            // 浅色模式：高不透明度白色磨砂 + 白色覆盖层叠加
            ZStack {
                RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                    .fill(.thickMaterial)
                RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            }
        }
    }
}

// MARK: - 设置页背景渐变
//
// 参考样式：柔和的多色渐变背景，卡片浮在上面

struct VSettingsBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if colorScheme == .dark {
                // 深色模式：暖橙/紫色调，收敛
                RadialGradient(
                    colors: [VColor.brandOrange.opacity(0.06), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 400
                )
                RadialGradient(
                    colors: [VColor.brandPurple.opacity(0.05), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 350
                )
            } else {
                // 浅色模式：明亮、柔和、品牌暖色
                RadialGradient(
                    colors: [VColor.brandOrange.opacity(0.15), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [VColor.brandPink.opacity(0.10), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 380
                )
                RadialGradient(
                    colors: [VColor.brandPurple.opacity(0.08), Color.clear],
                    center: UnitPoint(x: 0.8, y: 0.15),
                    startRadius: 0,
                    endRadius: 300
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 主按钮样式（浅色 = 黑胶囊 / 深色 = 白胶囊，带阴影）

struct VPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let pressed = configuration.isPressed

        return configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isDark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill((isDark ? Color.white : Color.black).opacity(pressed ? 0.60 : (isDark ? 0.90 : 0.85)))
            )
            .shadow(color: (isDark ? Color.white : Color.black).opacity(pressed ? 0 : 0.12),
                    radius: 8, x: 0, y: 4)
            .scaleEffect(pressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: pressed)
            .contentShape(Capsule())
    }
}

// MARK: - 次级按钮样式（胶囊描边）

struct VSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(pressed ? 0.06 : 0.00))
            )
            .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1.2))
            .scaleEffect(pressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: pressed)
            .contentShape(Capsule())
    }
}
