//
//  PrivacyPolicyView.swift
//  W6-04：内嵌隐私政策（WKWebView）。
//

import SwiftUI
import WebKit

struct PrivacyPolicyView: View {
    private let url = WebsiteURL.privacy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PrivacyWebView(url: url)
        }
        .frame(minWidth: 480, minHeight: 560)
    }
}

private struct PrivacyWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.load(URLRequest(url: url))
        return w
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
