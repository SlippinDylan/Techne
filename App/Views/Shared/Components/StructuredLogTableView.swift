import AppKit
import SwiftUI

struct StructuredLogTableView: NSViewRepresentable {
    let logs: [LogEntry]
    @Binding var selection: Set<UUID>

    private enum Layout {
        static let minimumRowHeight: CGFloat = 24
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 2
        static let rowSpacing: CGFloat = 2
        static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeScrollView()
        let tableView = makeTableView(delegate: context.coordinator)
        context.coordinator.tableView = tableView
        context.coordinator.logs = logs
        scrollView.documentView = tableView
        applySelection(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = context.coordinator.tableView ?? scrollView.documentView as? NSTableView else {
            return
        }

        context.coordinator.tableView = tableView
        context.coordinator.logs = logs
        tableView.reloadData()
        applySelection(on: tableView)
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller?.controlSize = .small
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        return scrollView
    }

    private func makeTableView(delegate: Coordinator) -> StructuredLogNSTableView {
        let tableView = StructuredLogNSTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("log-line"))
        column.resizingMask = .autoresizingMask
        column.width = 600
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: Layout.rowSpacing)
        tableView.rowHeight = Layout.minimumRowHeight
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = delegate
        tableView.dataSource = delegate
        tableView.onWidthDidChange = { [weak tableView] in
            guard let tableView else {
                return
            }

            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows))
        }
        return tableView
    }

    private func applySelection(on tableView: NSTableView) {
        let selectedIndexes = IndexSet(
            logs.enumerated().compactMap { index, log in
                selection.contains(log.id) ? index : nil
            }
        )

        if tableView.selectedRowIndexes != selectedIndexes {
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        @Binding private var selection: Set<UUID>
        fileprivate weak var tableView: NSTableView?
        fileprivate var logs: [LogEntry] = []

        init(selection: Binding<Set<UUID>>) {
            self._selection = selection
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            logs.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("structured-log-cell")
            let cellView: NSTableCellView

            if let reusedView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
                cellView = reusedView
            } else {
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byWordWrapping
                textField.maximumNumberOfLines = 0
                textField.cell?.wraps = true
                textField.cell?.usesSingleLineMode = false
                textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let view = NSTableCellView()
                view.identifier = identifier
                view.textField = textField
                view.addSubview(textField)
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                    textField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                    textField.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
                    textField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2)
                ])
                cellView = view
            }

            let log = logs[row]
            cellView.textField?.stringValue = log.formattedLine
            cellView.textField?.font = Layout.font
            cellView.textField?.textColor = color(for: log.level)
            return cellView
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard logs.indices.contains(row) else {
                return Layout.minimumRowHeight
            }

            let availableWidth = max(contentWidth(for: tableView) - (Layout.horizontalPadding * 2), 1)
            let boundingRect = (logs[row].formattedLine as NSString).boundingRect(
                with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: Layout.font]
            )

            return max(Layout.minimumRowHeight, ceil(boundingRect.height) + (Layout.verticalPadding * 2))
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else {
                return
            }

            selection = Set(
                tableView.selectedRowIndexes.compactMap { index in
                    guard logs.indices.contains(index) else {
                        return nil
                    }
                    return logs[index].id
                }
            )
        }

        private func color(for level: LogLevel) -> NSColor {
            switch level {
            case .info:
                return .labelColor
            case .success:
                return .systemGreen
            case .warning:
                return .systemOrange
            case .error:
                return .systemRed
            }
        }

        private func contentWidth(for tableView: NSTableView) -> CGFloat {
            if let columnWidth = tableView.tableColumns.first?.width {
                return columnWidth
            }

            return tableView.bounds.width
        }
    }
}

private final class StructuredLogNSTableView: NSTableView {
    var onWidthDidChange: (() -> Void)?

    private var lastMeasuredWidth: CGFloat = 0

    override func layout() {
        super.layout()

        let currentWidth = bounds.width
        guard abs(currentWidth - lastMeasuredWidth) > 0.5 else {
            return
        }

        lastMeasuredWidth = currentWidth
        onWidthDidChange?()
    }
}
