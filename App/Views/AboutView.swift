//
//  AboutView.swift
//  Techne
//
//  关于页面
//

import SwiftUI

struct AboutView: View {
    let updateController: ApplicationUpdateController

    /// 从 Bundle 中获取应用版本号
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主要内容
            Spacer()

            VStack(spacing: AppConfig.UI.extraLargeSpacing) {
                // 应用图标
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
                    .shadow(radius: 10)

                VStack(spacing: AppConfig.UI.mediumSpacing) {
                    Text("Techne")
                        .font(.system(size: 32, weight: .bold))

                    Text("版本 \(appVersion)")
                        .font(.system(size: AppConfig.UI.mediumFontSize))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Button("检查更新…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
                .padding(.bottom, AppConfig.UI.mediumSpacing)

                Text("Copyright © 2025-2026 SlippinDylan Studio")
                    .font(.system(size: AppConfig.UI.mediumFontSize))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    AboutView(updateController: ApplicationUpdateController(updaterEnabled: false))
}
