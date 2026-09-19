//
//  LogView.swift
//  Techne
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
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("搜索日志..."))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                levelFilterMenu
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                if !selection.isEmpty {
                    Button(action: copySelectedLogs) {
                        Label("复制选中", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                    }
                    .help("复制选中")
                }

                Button(action: copyAllLogs) {
                    Label("复制所有", systemImage: "doc.on.doc.fill")
                        .labelStyle(.iconOnly)
                }
                .help("复制所有")
                .disabled(filteredLogs.isEmpty)
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    logService.clearLogs()
                    selection.removeAll()
                } label: {
                    Label("清空日志", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("清空日志")
                .disabled(logService.logs.isEmpty)
            }
        }
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
            StatCardData(icon: "doc.text.fill", label: AppLocalized("总日志数"), value: "\(logService.logs.count)"),
            StatCardData(icon: "checkmark.circle.fill", label: AppLocalized("成功"), value: "\(successCount)", iconColor: .green),
            StatCardData(icon: "exclamationmark.triangle.fill", label: AppLocalized("警告"), value: "\(warningCount)", iconColor: .orange),
            StatCardData(icon: "xmark.circle.fill", label: AppLocalized("错误"), value: "\(errorCount)", iconColor: .red)
        ])
    }

    // MARK: - Log Content View

    private var logContentView: some View {
        logListCard
        .padding(.horizontal, AppConfig.UI.extraLargePadding)
        .padding(.bottom, AppConfig.UI.extraLargePadding)
    }

    private var levelFilterMenu: some View {
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
            Label(
                selectedLevel.map { AppLocalized($0.rawValue) } ?? AppLocalized("全部级别"),
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.iconOnly)
        }
        .help(selectedLevel.map { AppLocalized($0.rawValue) } ?? AppLocalized("全部级别"))
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
