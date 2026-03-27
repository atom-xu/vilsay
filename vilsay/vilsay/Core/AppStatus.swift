//
//  AppStatus.swift
//  vilsay
//

import SwiftUI

/// 菜单栏与悬浮按钮共用状态（UI/UX 第 4 章）。
enum AppStatus: Equatable, CaseIterable, Sendable, CustomStringConvertible {
    /// 待机：灰色麦克风轮廓
    case idle
    /// 录音中：红色实心 + 脉冲
    case recording
    /// 处理中：旋转指示（ASR 等）
    case processing
    /// 注入中：润色文本写入剪贴板/目标应用（`VILSAY_TECH_SPEC_SUPPLEMENT` §1.2）
    case injecting
    /// 改词模式：蓝色铅笔
    case editMode
    /// 错误：橙色感叹号
    case error
    /// 需注意（如润色降级、API 未配置）：橙色提示
    case attention

    var description: String {
        switch self {
        case .idle: "idle"
        case .recording: "recording"
        case .processing: "processing"
        case .injecting: "injecting"
        case .editMode: "editMode"
        case .error: "error"
        case .attention: "attention"
        }
    }

    var menuBarSymbolName: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .processing: "mic.badge.ellipsis"
        case .injecting: "mic.badge.ellipsis"
        case .editMode: "pencil.and.outline"
        case .error: "mic.badge.xmark"
        case .attention: "mic.badge.exclamationmark"
        }
    }

    var menuBarColor: Color {
        switch self {
        case .idle: .secondary
        case .recording: .red
        case .processing: .primary
        case .injecting: .primary
        case .editMode: .blue
        case .error: .orange
        case .attention: .orange
        }
    }
}

enum TriggerMode: String, CaseIterable, Identifiable {
    case push
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: "长按"
        case .toggle: "单击"
        }
    }
}
