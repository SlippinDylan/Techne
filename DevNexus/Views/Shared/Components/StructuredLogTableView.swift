import AppKit
import SwiftUI

struct StructuredLogTableView: NSViewRepresentable {
    let logs: [LogEntry]
    @Binding var selection: Set<UUID>

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> ConsoleViewportScrollView {
        let scrollView = ConsoleViewportScrollView()
        let tableView = makeTableView(delegate: context.coordinator)
        context.coordinator.tableView = tableView
        context.coordinator.logs = logs
        scrollView.documentView = tableView
        applySelection(on: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: ConsoleViewportScrollView, context: Context) {
        guard let tableView = context.coordinator.tableView ?? scrollView.documentView as? NSTableView else {
            return
        }

        context.coordinator.tableView = tableView
        context.coordinator.logs = logs
        tableView.reloadData()
        applySelection(on: tableView)
    }

    private func makeTableView(delegate: Coordinator) -> NSTableView {
        let tableView = NSTableView(frame: .zero)
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
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.rowHeight = 24
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = delegate
        tableView.dataSource = delegate
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
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 1
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
            cellView.textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            cellView.textField?.textColor = color(for: log.level)
            return cellView
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
    }
}
