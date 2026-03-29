//
//  MainNavItem.swift
//  vilsay
//

import SwiftUI

/// 主窗口侧边栏导航项。
enum MainNavItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case history
    case dictionary
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:  return "首页"
        case .history:    return "历史记录"
        case .dictionary: return "词典"
        case .profile:    return "语言画像"
        case .settings:   return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:  return "house"
        case .history:    return "clock.arrow.circlepath"
        case .dictionary: return "book"
        case .profile:    return "brain.head.profile"
        case .settings:   return "gearshape"
        }
    }
}
