import AppKit

/// Меню всех текстов с поиском: печатаешь — список сужается, ↑↓ выбор, Enter вставить, Esc закрыть.
final class SearchPanel: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    static let shared = SearchPanel()

    private var panel: NSPanel?
    private let field = NSSearchField()
    private let table = NSTableView()
    private var all: [SearchItem] = []
    private var shown: [SearchItem] = []
    private var previous: NSRunningApplication?
    private var onPick: ((String) -> Void)?
    private var closing = false

    var isVisible: Bool { panel?.isVisible == true }

    func show(_ items: [SearchItem], onPick: @escaping (String) -> Void) {
        previous = NSWorkspace.shared.frontmostApplication
        all = items
        self.onPick = onPick
        let p = panel ?? makePanel()
        panel = p
        field.stringValue = ""
        refilter()

        // у курсора, но не за краем экрана
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x, y: mouse.y - p.frame.height)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - p.frame.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - p.frame.height)
        }
        p.setFrameOrigin(origin)
        p.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(field)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        p.title = "Найти текст"
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.delegate = self

        field.placeholderString = "Начни печатать название или кусок текста"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("t"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 38
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(pickSelected)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let v = NSView()
        v.addSubview(field)
        v.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        p.contentView = v
        return p
    }

    private func refilter() {
        shown = SearchItem.filter(all, field.stringValue)
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); table.scrollRowToVisible(0) }
    }

    // MARK: выбор

    @objc private func pickSelected() {
        let row = table.selectedRow
        guard shown.indices.contains(row) else { return }
        let text = shown[row].text
        dismiss(refocus: true)
        // ждём, пока вернётся окно, куда вставляем
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.onPick?(text) }
    }

    private func dismiss(refocus: Bool) {
        guard let p = panel, p.isVisible, !closing else { return }
        closing = true
        p.orderOut(nil)
        closing = false
        if refocus, let previous, previous != .current { previous.activate() }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss(refocus: false) }

    // MARK: поле поиска

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): pickSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty { dismiss(refocus: true) } else { field.stringValue = ""; refilter() }
            return true
        default: return false
        }
    }

    private func move(_ d: Int) {
        guard !shown.isEmpty else { return }
        let r = min(max(table.selectedRow + d, 0), shown.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    // MARK: таблица

    func numberOfRows(in tableView: NSTableView) -> Int { shown.isEmpty ? 1 : shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = NSMutableAttributedString()
        if shown.isEmpty {
            s.append(NSAttributedString(string: "Ничего не нашлось", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        } else {
            let it = shown[row]
            var head = it.title
            if !it.path.isEmpty { head = it.path + " › " + head }
            s.append(NSAttributedString(string: head, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]))
            if !it.hotkey.isEmpty {
                s.append(NSAttributedString(string: "   " + it.hotkey, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            let one = it.text.replacingOccurrences(of: "\n", with: " ").prefix(120)
            s.append(NSAttributedString(string: "\n" + one, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let label = NSTextField(labelWithAttributedString: s)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        return label
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !shown.isEmpty }
}
