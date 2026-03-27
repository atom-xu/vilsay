//
//  PlaceholderToggle.swift
//  vilsay
//

import SwiftUI

/// UI/UX 第六章：统一「即将推出」占位样式。
struct PlaceholderToggle: View {
    let label: String

    var body: some View {
        HStack {
            Text(label).opacity(0.4)
            Spacer()
            Toggle("", isOn: .constant(false))
                .disabled(true)
                .opacity(0.4)
        }
        .help("即将推出")
        .allowsHitTesting(false)
    }
}
