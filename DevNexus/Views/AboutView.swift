//
//  AboutView.swift
//  DevNexus
//
//  关于页面
//

import SwiftUI

struct AboutView: View {
    /// 从 Bundle 中获取应用版本号
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 主要内容
            Spacer()

            VStack(spacing: AppConfig.UI.extraLargeSpacing) {
                // 应用图标
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
                        .shadow(radius: 10)
                } else {
                    Image(systemName: "percent")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                        .frame(width: 128, height: 128)
                        .background(.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
                }

                VStack(spacing: AppConfig.UI.mediumSpacing) {
                    Text("DevNexus")
                        .font(.system(size: 32, weight: .bold))

                    Text("版本 \(appVersion)")
                        .font(.system(size: AppConfig.UI.mediumFontSize))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(width: 300)
                    .padding(.vertical, AppConfig.UI.largeSpacing)

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
    AboutView()
}
