import AppKit

/// Окошко с вопросами из %ask:...% перед вставкой.
enum FormDialog {
    /// Ответы по вопросам или nil, если нажали «Отмена».
    static func ask(_ questions: [String]) -> [String: String]? {
        let alert = NSAlert()
        alert.messageText = "Заполни перед вставкой"
        alert.addButton(withTitle: "Вставить")
        alert.addButton(withTitle: "Отмена")

        let fields = questions.map { q -> NSTextField in
            let f = NSTextField(string: "")
            f.placeholderString = q
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 260).isActive = true
            return f
        }
        let grid = NSGridView(views: zip(questions, fields).map { q, f in
            let label = NSTextField(labelWithString: q + ":")
            label.alignment = .right
            return [label, f]
        })
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid

        // Tab переходит к следующему полю
        for (a, b) in zip(fields, fields.dropFirst()) { a.nextKeyView = b }
        alert.window.initialFirstResponder = fields.first

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var answers: [String: String] = [:]
        for (q, f) in zip(questions, fields) { answers[q] = f.stringValue }
        return answers
    }
}
