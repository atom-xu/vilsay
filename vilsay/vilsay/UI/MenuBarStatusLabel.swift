//
//  MenuBarStatusLabel.swift
//

import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject private var state = AppState.shared

    private var permissionWarning: Bool {
        !state.microphoneGranted || !state.accessibilityGranted
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            barIconImage
                .frame(width: 22, height: 16)

            if state.dictionaryBadgeCount > 0 {
                Text("\(state.dictionaryBadgeCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(VColor.fail))
                    .offset(x: 8, y: -6)
            }
        }
        .frame(minWidth: 28, minHeight: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vilsay")
        .accessibilityIdentifier("vilsay.menubar.extra")
        .help(helpText)
    }

    // MARK: - 根据状态选 NSImage

    @ViewBuilder
    private var barIconImage: some View {
        if permissionWarning || state.status == .error || state.status == .attention {
            // 橙色警告
            Image(nsImage: Self.makeBarImage(nsColors: Array(repeating:
                NSColor(red: 251/255, green: 146/255, blue: 60/255, alpha: 1), count: 4
            ), template: false))
            .renderingMode(.original)
        } else {
            switch state.status {
            case .recording, .editMode:
                // 橙 → 粉 → 紫 → 靛（4 柱各一色）
                Image(nsImage: Self.makeBarImage(nsColors: [
                    NSColor(red: 251/255, green: 146/255, blue: 60/255,  alpha: 1),
                    NSColor(red: 244/255, green: 114/255, blue: 182/255, alpha: 1),
                    NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 1),
                    NSColor(red: 129/255, green: 140/255, blue: 248/255, alpha: 1),
                ], template: false))
                .renderingMode(.original)

            case .processing, .injecting:
                // 紫色半透明
                Image(nsImage: Self.makeBarImage(nsColors: Array(repeating:
                    NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 0.6), count: 4
                ), template: false))
                .renderingMode(.original)

            case .idle, .error, .attention:
                // Template image：macOS 自动适配亮/暗模式及 Vibrancy
                Image(nsImage: Self.idleTemplateImage)
                    .renderingMode(.template)
            }
        }
    }

    // MARK: - NSImage 工厂（静态，可复用）

    /// Idle 专用模板图（一次生成，反复复用）
    private static let idleTemplateImage: NSImage = makeBarImage(
        nsColors: Array(repeating: NSColor.black, count: 4),
        template: true
    )

    /// 将 4 根柱子画成 NSImage
    /// - Parameters:
    ///   - nsColors: 4 根柱的 NSColor（按索引对应）
    ///   - template: true → 系统自动反色（菜单栏 idle 专用）
    private static func makeBarImage(nsColors: [NSColor], template: Bool) -> NSImage {
        let heights: [CGFloat] = [8, 14, 11, 6]
        let barW: CGFloat   = 3
        let gap: CGFloat    = 3
        let totalW          = 4 * barW + 3 * gap   // = 21
        let imgW: CGFloat   = 22
        let imgH: CGFloat   = 16
        let startX          = (imgW - totalW) / 2  // ≈ 0.5

        let image = NSImage(size: NSSize(width: imgW, height: imgH), flipped: false) { _ in
            for i in 0..<4 {
                let color = i < nsColors.count ? nsColors[i] : (nsColors.last ?? .labelColor)
                color.setFill()
                let h = heights[i]
                let x = startX + CGFloat(i) * (barW + gap)
                let y = (imgH - h) / 2
                let rect = NSRect(x: x, y: y, width: barW, height: h)
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                path.fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }

    // MARK: - Tooltip

    private var helpText: String {
        var parts: [String] = []
        if let d = state.diagnosticsExclusionHint, !d.isEmpty { parts.append(d) }
        if let hint = state.localWhisperStatusHint, !hint.isEmpty { parts.append(hint) }
        if let msg = state.polishAttentionMessage, !msg.isEmpty { parts.append(msg) }
        if let err = state.lastPipelineError, !err.isEmpty { parts.append(err) }
        return parts.joined(separator: "\n")
    }
}
