import SwiftUI

struct ManualBrowserLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let browsers: [Browser]
    let onLaunch: @Sendable (BrowserLaunchRequest) async -> Result<Void, Error>

    @State private var selectedBrowserID: String?
    @State private var urlText = ""
    @State private var isLaunching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.extraLargeSpacing) {
            Text("新建浏览器实例")
                .font(.system(size: AppConfig.UI.titleFontSize, weight: .semibold))

            Text("可选填写地址；留空时仅启动独立浏览器实例。")
                .font(.system(size: AppConfig.UI.smallFontSize))
                .foregroundStyle(.secondary)

            Picker("浏览器", selection: $selectedBrowserID) {
                ForEach(browsers) { browser in
                    Text(browser.displayName).tag(Optional(browser.id))
                }
            }
            .pickerStyle(.menu)

            TextField("可选地址，例如 http://localhost:5173", text: $urlText)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: AppConfig.UI.largeSpacing) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .disabled(isLaunching)

                Button("启动") {
                    launch()
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .disabled(selectedBrowserID == nil || isLaunching)
            }
        }
        .padding(AppConfig.UI.extraLargePadding)
        .frame(width: 520, height: 280)
        .onAppear {
            selectedBrowserID = selectedBrowserID ?? browsers.first?.id
        }
    }

    private func launch() {
        guard let browser = browsers.first(where: { $0.id == selectedBrowserID }) else {
            return
        }

        isLaunching = true
        errorMessage = nil

        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = BrowserLaunchRequest.manual(
            browser: browser,
            url: trimmedURL.isEmpty ? nil : trimmedURL,
            launchSource: "dev-environment-manual"
        )

        Task {
            let result = await onLaunch(request)
            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    isLaunching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ManualBrowserLaunchSheet(browsers: [], onLaunch: { _ in .success(()) })
}
