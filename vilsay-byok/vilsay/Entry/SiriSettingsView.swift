//
//  SiriSettingsView.swift
//  Siri 禁用/启用设置界面
//

import SwiftUI

struct SiriSettingsView: View {
    @State private var isSiriDisabled = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Siri 键设置")
                    .font(.headline)
            }
            
            Divider()
            
            // 状态显示
            HStack(spacing: 12) {
                Image(systemName: isSiriDisabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(isSiriDisabled ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(isSiriDisabled ? "系统 Siri 已禁用" : "系统 Siri 已启用")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(isSiriDisabled ? "可以使用 Siri 键作为热键" : "需要禁用才能使用 Siri 键")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // 说明文字
            Text("💡 提示")
                .font(.caption)
                .fontWeight(.semibold)
            
            Text("要使用 Siri 键（Touch Bar 上的 Siri 按钮或键盘上的 Siri 键）作为应用热键，需要先禁用系统 Siri。禁用后，Siri 将不再响应，但你可以随时重新启用。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // 操作按钮
            HStack {
                if isSiriDisabled {
                    Button {
                        Task {
                            await toggleSiri(enable: true)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重新启用系统 Siri")
                        }
                    }
                    .disabled(isProcessing)
                } else {
                    Button {
                        Task {
                            await toggleSiri(enable: false)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("禁用系统 Siri")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 8)
                }
            }
            
            // 错误提示
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .onAppear {
            checkSiriStatus()
        }
        .alert("操作成功", isPresented: $showSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(isSiriDisabled ? "系统 Siri 已禁用，现在可以使用 Siri 键作为热键了。" : "系统 Siri 已重新启用。")
        }
    }
    
    // MARK: - Actions
    
    private func checkSiriStatus() {
        isSiriDisabled = SiriManager.isSiriDisabled()
    }
    
    private func toggleSiri(enable: Bool) async {
        isProcessing = true
        errorMessage = nil
        
        do {
            if enable {
                try await SiriManager.enableSiri()
            } else {
                try await SiriManager.disableSiri()
            }
            
            // 等待系统生效
            try await Task.sleep(for: .seconds(1))
            
            await MainActor.run {
                checkSiriStatus()
                showSuccessAlert = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "操作失败: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isProcessing = false
        }
    }
}

// MARK: - Preview
#Preview {
    SiriSettingsView()
        .frame(width: 400)
}
