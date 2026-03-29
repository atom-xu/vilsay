//
//  SidebarView.swift
//  vilsay
//

import SwiftUI

/// 主窗口侧边栏
struct SidebarView: View {
    @Binding var selection: MainNavItem
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Logo 区（不用 List 承接导航，避免 List/NSTableView 在 Logo 下方画系统横线）
            HStack(spacing: VSpacing.sm) {
                VilsayMarkSidebar()
                Text("Vilsay")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach([MainNavItem.dashboard, .history, .dictionary, .profile], id: \.self) { item in
                        sidebarNavRow(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)

            sidebarFooter
        }
        // 覆盖 NavigationSplitView 在亮色模式下给 sidebar 列自动加的材质背景，消除线框感
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarNavRow(_ item: MainNavItem) -> some View {
        let isSelected = selection == item
        let badgeCount = item == .dictionary ? state.candidatesCount : 0
        return Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 11))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? VColor.accent.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    // MARK: - 底部

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if auth.isAuthenticated {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(VColor.accent)
                        Text(auth.userEmail ?? "已登录")
                            .font(.caption)
                            .lineLimit(1)
                    }

                    if auth.usageQuota > 0 {
                        let ratio = min(1.0, Double(auth.usageUsed) / Double(auth.usageQuota))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("已使用 \(auth.usageUsed) / \(auth.usageQuota) 次")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                    Capsule()
                                        .fill(auth.isQuotaExceeded ? VColor.warn : VColor.accent)
                                        .frame(width: max(2, geo.size.width * ratio))
                                }
                            }
                            .frame(height: 4)
                        }
                    }

                    Button("升级 Pro") {
                        NSWorkspace.shared.open(WebsiteURL.pricing)
                    }
                    .buttonStyle(VPrimaryButtonStyle())
                    .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.secondary)
                        Text("未登录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("登录 / 注册") {
                        state.showLoginSheet = true
                    }
                    .buttonStyle(VSecondaryButtonStyle())
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // 底部图标栏（设置 + 联系 + 官网 + 版本）
            HStack(spacing: 12) {
                Button {
                    selection = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(selection == .settings ? VColor.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help("设置")

                Button {
                    if let url = URL(string: "mailto:shay1230xh@163.com?subject=Vilsay%20%E5%8F%8D%E9%A6%88") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("联系我们：shay1230xh@163.com")

                Button {
                    NSWorkspace.shared.open(WebsiteURL.home)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("进入官网")

                Spacer()

                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
