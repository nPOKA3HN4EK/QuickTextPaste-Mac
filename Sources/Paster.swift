import AppKit
import ApplicationServices

/// Вставляет текст в активное окно: кладёт в буфер и жмёт ⌘V, потом возвращает старый буфер.
final class Paster {
    static let shared = Paster()
    private let queue = DispatchQueue(label: "qtp.paster")
    private var busy = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func paste(_ text: String) {
        guard Self.isTrusted else {
            let alert = NSAlert()
            alert.messageText = "Нужно разрешение «Универсальный доступ»"
            alert.informativeText = "Без него macOS не даёт вставлять текст в другие программы.\n\nОткрой Системные настройки → Конфиденциальность и безопасность → Универсальный доступ и включи QuickTextPaste. Если он уже включён, выключи и включи снова."
            alert.addButton(withTitle: "Открыть настройки")
            alert.addButton(withTitle: "Позже")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                Self.promptAccessibility()
                Self.openAccessibilitySettings()
            }
            return
        }
        guard !busy else { return }
        busy = true

        let settings = Store.shared.settings
        let pb = NSPasteboard.general
        let clipboard = pb.string(forType: .string) ?? ""
        let saved = settings.restoreClipboard ? Self.snapshot(pb) : nil
        let actions = TextProcessor(dateFormat: settings.dateFormat, timeFormat: settings.timeFormat)
            .process(text, clipboard: clipboard)
        let delay = UInt32(max(20, settings.pasteDelayMs)) * 1000
        var pasted = false

        queue.async {
            self.waitForModifiersReleased()
            for action in actions {
                switch action {
                case .text(let s):
                    DispatchQueue.main.sync { Self.put(pb, string: s, html: nil) }
                    usleep(20_000)
                    self.press(9, flags: .maskCommand) // ⌘V
                    usleep(delay)
                    pasted = true
                case .html(let h):
                    DispatchQueue.main.sync { Self.put(pb, string: Self.stripTags(h), html: h) }
                    usleep(20_000)
                    self.press(9, flags: .maskCommand)
                    usleep(delay)
                    pasted = true
                case .sleep(let ms):
                    usleep(UInt32(ms) * 1000)
                case .key(let k):
                    self.press(k, flags: [])
                    usleep(30_000)
                case .run(let target):
                    DispatchQueue.main.sync { Self.open(target) }
                    usleep(200_000)
                }
            }
            // даём программе время прочитать буфер, потом возвращаем старое содержимое
            if pasted { usleep(max(300_000, delay * 3)) }
            DispatchQueue.main.async {
                if pasted, let saved { Self.restore(pb, saved) }
                self.busy = false
            }
        }
    }

    // MARK: клавиатура

    private func waitForModifiersReleased() {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<100 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            usleep(10_000)
        }
    }

    private func press(_ key: UInt16, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(8_000)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: буфер обмена

    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private static func put(_ pb: NSPasteboard, string: String, html: String?) {
        pb.clearContents()
        pb.setString(string, forType: .string)
        if let html { pb.setString(html, forType: .html) }
        pb.setData(Data(), forType: transient) // менеджеры буфера не будут это запоминать
    }

    static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
    }

    static func restore(_ pb: NSPasteboard, _ snap: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !snap.isEmpty else { return }
        let items = snap.map { d -> NSPasteboardItem in
            let it = NSPasteboardItem()
            for (t, v) in d { it.setData(v, forType: t) }
            return it
        }
        pb.writeObjects(items)
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: run:

    static func open(_ target: String) {
        let expanded = (target as NSString).expandingTildeInPath
        if target.contains("://"), let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        } else if FileManager.default.fileExists(atPath: expanded) {
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
        } else if target.hasPrefix("www."), let url = URL(string: "https://" + target) {
            NSWorkspace.shared.open(url)
        } else {
            // по имени программы, например «Telegram» или «Safari»
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", target]
            try? p.run()
        }
    }
}
