//
//  LogView.swift
//  DevNexus
//
//  Created by SlippinDylan on 2025/12/15.
//

import SwiftUI

/// 日志视图
/// 显示应用中的所有操作日志
struct LogView: View {
    @Environment(LogService.self) var logService
    @State private var selectedLevel: LogLevel?
    @State private var searchText = ""
    @State private var selection = Set<UUID>()
    private let consolePanelConfiguration = ConsolePanelStyle.configuration(for: .logWindow)

    var body: some View {
        VStack(spacing: 0) {
            // 固定的统计卡片区域
            statisticsSection
                .padding(AppConfig.UI.extraLargePadding)

            // 可滚动的内容区域
            logContentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selection = Self.reconciledSelection(selection, visibleLogs: filteredLogs)
        }
        .onChange(of: filteredLogIDs) { _, _ in
            selection = Self.reconciledSelection(selection, visibleLogs: filteredLogs)
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        StatCardsRow(cards: [
            StatCardData(icon: "doc.text.fill", label: "总日志数", value: "\(logService.logs.count)"),
            StatCardData(icon: "checkmark.circle.fill", label: "成功", value: "\(successCount)", iconColor: .green),
            StatCardData(icon: "exclamationmark.triangle.fill", label: "警告", value: "\(warningCount)", iconColor: .orange),
            StatCardData(icon: "xmark.circle.fill", label: "错误", value: "\(errorCount)", iconColor: .red)
        ])
    }

    // MARK: - Log Content View

    private var logContentView: some View {
        VStack(spacing: AppConfig.UI.largeSpacing) {
            filterBarCard
            logListCard
        }
        .padding(.horizontal, AppConfig.UI.extraLargePadding)
        .padding(.bottom, AppConfig.UI.extraLargePadding)
    }

    // MARK: - Filter Bar Card

    private var filterBarCard: some View {
        HStack(spacing: AppConfig.UI.largeSpacing) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索日志...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppConfig.UI.mediumPadding)
            .padding(.vertical, AppConfig.UI.mediumSpacing)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))

            // 级别筛选
            Menu {
                Button("全部") {
                    selectedLevel = nil
                }
                Divider()
                Button("信息") {
                    selectedLevel = .info
                }
                Button("成功") {
                    selectedLevel = .success
                }
                Button("警告") {
                    selectedLevel = .warning
                }
                Button("错误") {
                    selectedLevel = .error
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(selectedLevel?.rawValue ?? "全部级别")
                }
                .padding(.horizontal, AppConfig.UI.mediumPadding)
                .padding(.vertical, AppConfig.UI.mediumSpacing)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            }
            .buttonStyle(.plain)

            Spacer()

            // 显示选中数量
            if !selection.isEmpty {
                Text("已选择 \(selection.count) 条")
                    .font(.system(size: AppConfig.UI.smallFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppConfig.UI.mediumPadding)
                    .padding(.vertical, AppConfig.UI.mediumSpacing)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.mediumCornerRadius))
            }

            // 复制选中按钮（仅在有选中时显示）
            if !selection.isEmpty {
                CleanMyMacButton(
                    title: "复制选中",
                    icon: "doc.on.doc",
                    action: {
                        copySelectedLogs()
                    },
                    style: .secondary,
                    isDestructive: false
                )
            }

            // 复制所有日志按钮
            CleanMyMacButton(
                title: "复制所有",
                icon: "doc.on.doc.fill",
                action: {
                    copyAllLogs()
                },
                style: .primary,
                isDestructive: false
            )

            // 清空按钮
            CleanMyMacButton(
                title: "清空日志",
                icon: "trash",
                action: {
                    logService.clearLogs()
                    selection.removeAll()
                },
                style: .secondary,
                isDestructive: true
            )
        }
        .padding(AppConfig.UI.largePadding)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppConfig.UI.largeCornerRadius))
    }

    // MARK: - Log List Card

    private var logListCard: some View {
        ConsolePanelContainer(configuration: consolePanelConfiguration) {
            logViewport
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var logViewport: some View {
        Group {
            if filteredLogs.isEmpty {
                emptyLogViewport
            } else {
                structuredLogList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(consolePanelConfiguration.palette.viewportBackground.resolvedColor)
        .clipShape(RoundedRectangle(cornerRadius: consolePanelConfiguration.viewport.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: consolePanelConfiguration.viewport.cornerRadius)
                .stroke(consolePanelConfiguration.palette.viewportBorder.resolvedColor, lineWidth: 1)
        )
    }

    private var structuredLogList: some View {
        StructuredLogTableView(logs: filteredLogs, selection: $selection)
    }

    private var emptyLogViewport: some View {
        VStack(spacing: AppConfig.UI.mediumSpacing) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No logs yet")
                .font(.system(size: AppConfig.UI.mediumFontSize, weight: .medium, design: .monospaced))

            Text("Logs will appear here")
                .font(.system(size: AppConfig.UI.smallFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(consolePanelConfiguration.viewport.padding)
    }

    // MARK: - Computed Properties

    private var filteredLogs: [LogEntry] {
        var logs = logService.logs

        // 按级别筛选
        if let level = selectedLevel {
            logs = logs.filter { $0.level == level }
        }

        // 按搜索文本筛选
        if !searchText.isEmpty {
            logs = logs.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }

        return logs
    }

    private var filteredLogIDs: [UUID] {
        filteredLogs.map(\.id)
    }

    private var successCount: Int {
        logService.logs.filter { $0.level == .success }.count
    }

    private var warningCount: Int {
        logService.logs.filter { $0.level == .warning }.count
    }

    private var errorCount: Int {
        logService.logs.filter { $0.level == .error }.count
    }

    // MARK: - Helper Methods

    private func copySelectedLogs() {
        let selectedLogs = filteredLogs.filter { selection.contains($0.id) }
        copyLogs(selectedLogs)
    }

    private func copyAllLogs() {
        copyLogs(filteredLogs)
    }

    private func copyLogs(_ logs: [LogEntry]) {
        let text = logs.map(\.formattedLine).joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func reconciledSelection(_ currentSelection: Set<UUID>, visibleLogs: [LogEntry]) -> Set<UUID> {
        let visibleLogIDs = Set(visibleLogs.map(\.id))
        return currentSelection.intersection(visibleLogIDs)
    }
}

#Preview {
    LogView()
        .environment(LogService.shared)
}
