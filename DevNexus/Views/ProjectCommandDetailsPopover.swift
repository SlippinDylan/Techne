import SwiftUI

struct ProjectCommandDetails: Equatable {
    struct Section: Identifiable, Equatable {
        let title: String
        let value: String

        var id: String { title }
        var isConfigured: Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    let profileDisplayName: String
    let sections: [Section]

    init(project: Project) {
        let trimmedProfileName = project.commandProfileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        profileDisplayName = trimmedProfileName.isEmpty ? "自定义命令" : trimmedProfileName
        sections = [
            Section(title: "启动命令", value: project.startCommand),
            Section(title: "安装依赖命令", value: project.installCommand),
            Section(title: "构建命令", value: project.buildCommand),
            Section(title: "清理命令", value: project.cleanCommand),
            Section(title: "停止命令", value: project.stopCommand),
            Section(title: "丢弃更改命令", value: project.discardChangesCommand),
            Section(title: "安装策略", value: project.installStrategy.displayName)
        ]
    }
}

struct ProjectCommandDetailsPopover: View {
    private enum Layout {
        static let width: CGFloat = 560
    }

    let details: ProjectCommandDetails

    init(project: Project) {
        self.details = ProjectCommandDetails(project: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConfig.UI.largeSpacing) {
            VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                Text(details.profileDisplayName)
                    .font(.system(size: AppConfig.UI.mediumFontSize + 2, weight: .semibold))

                Text("当前项目卡片展示的是项目自己的命令快照。")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)
            }

            ForEach(details.sections) { section in
                VStack(alignment: .leading, spacing: AppConfig.UI.smallSpacing) {
                    Text(section.title)
                        .font(.system(size: AppConfig.UI.smallFontSize, weight: .medium))
                        .foregroundStyle(.secondary)

                    if section.isConfigured {
                        Text(section.value)
                            .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppConfig.UI.mediumPadding)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("未配置")
                            .font(.system(size: AppConfig.UI.smallFontSize))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppConfig.UI.mediumPadding)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
                    }
                }
            }
        }
        .frame(width: Layout.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(AppConfig.UI.extraLargePadding)
    }
}

private extension InstallStrategy {
    var displayName: String {
        switch self {
        case .never:
            return "从不安装"
        case .ifMissing:
            return "缺失时安装"
        case .always:
            return "总是安装"
        }
    }
}

#Preview {
    ProjectCommandDetailsPopover(
        project: Project(
            name: "frontend-app",
            path: "/tmp/frontend-app",
            type: .devServer,
            startCommand: "pnpm dev",
            buildCommand: "pnpm build",
            cleanCommand: "rm -rf dist .vite",
            installCommand: "pnpm install",
            stopCommand: "pkill -f vite",
            discardChangesCommand: "git restore . && git clean -fd",
            commandProfileName: "Vite + pnpm",
            installStrategy: .ifMissing
        )
    )
}
