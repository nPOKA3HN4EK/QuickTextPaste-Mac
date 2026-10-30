import Foundation

/// Что сделать при вставке, по шагам.
enum PasteAction: Equatable {
    case text(String)
    case html(String)
    case sleep(Int)      // миллисекунды
    case key(UInt16)     // виртуальный код клавиши
    case run(String)     // открыть сайт / файл / программу
    case typeText(String) // напечатать символы напрямую, без буфера (для разделителя автотекста)
    case backspace(Int)  // стереть столько символов (для сокращения автотекста)
}

/// Пункт всплывающего меню (MenuName: / MenuBreak:).
struct MenuDef: Equatable {
    var label: String
    var text: String
    var isSeparator = false
}

struct CommandHelp: Identifiable {
    var token: String
    var help: String
    var onNewLine = false
    var id: String { token }

    static let all: [CommandHelp] = [
        CommandHelp(token: "%DATE%", help: "сегодняшняя дата"),
        CommandHelp(token: "%TIME%", help: "текущее время"),
        CommandHelp(token: "%DATETIME%", help: "дата и время"),
        CommandHelp(token: "%DATE:yyyy-MM-dd%", help: "дата в своём формате"),
        CommandHelp(token: "%sleep_200%", help: "пауза 200 мс (число любое)"),
        CommandHelp(token: "%send_tab%", help: "нажать Tab"),
        CommandHelp(token: "%send_enter%", help: "нажать Enter"),
        CommandHelp(token: "%send_esc%", help: "нажать Esc"),
        CommandHelp(token: "%send_up%", help: "стрелка вверх (также down/left/right)"),
        CommandHelp(token: "%TAB%", help: "символ табуляции"),
        CommandHelp(token: "%copy_text%", help: "текст из буфера обмена"),
        CommandHelp(token: "%copy_text_uc%", help: "буфер ЗАГЛАВНЫМИ"),
        CommandHelp(token: "%copy_text_lc%", help: "буфер строчными"),
        CommandHelp(token: "%copy_text_ucFirstWord%", help: "буфер, первая буква заглавная"),
        CommandHelp(token: "%copy_text_lc_ucFirstWord%", help: "буфер строчными, первая заглавная"),
        CommandHelp(token: "%copy_text_ucFirstAllWords%", help: "буфер, Каждое Слово С Заглавной"),
        CommandHelp(token: "%copy_text_lc_ucFirstAllWords%", help: "буфер строчными, Каждое Слово С Заглавной"),
        CommandHelp(token: "%copy_text_mix_lc_uc%", help: "буфер вПеРеМеШкУ"),
        CommandHelp(token: "%copy_text_escape%", help: "буфер с экранированием \\ \" '"),
        CommandHelp(token: "%cpy_txt_urlencode%", help: "буфер для вставки в ссылку"),
        CommandHelp(token: "%USERNAME%", help: "имя пользователя Mac"),
        CommandHelp(token: "%UserProfile%", help: "домашняя папка"),
        CommandHelp(token: "%pastehtml%", help: "в самом начале: вставить текст как HTML"),
        CommandHelp(token: "run:", help: "с новой строки: открыть сайт, файл или программу", onNewLine: true),
        CommandHelp(token: "MenuName:", help: "с новой строки: пункт всплывающего меню", onNewLine: true),
        CommandHelp(token: "MenuBreak:", help: "с новой строки: разделитель в меню", onNewLine: true),
    ]
}

struct TextProcessor {
    var dateFormat = "dd.MM.yyyy"
    var timeFormat = "HH:mm"
    var now = Date()

    static let sendKeys: [String: UInt16] = [
        "tab": 48, "enter": 36, "return": 36, "esc": 53, "escape": 53, "space": 49, "backspace": 51,
        "delete": 117, "del": 117, "up": 126, "down": 125, "left": 123, "right": 124, "home": 115, "end": 119,
    ]

    private static let tokenRegex = try! NSRegularExpression(pattern: "%([A-Za-z][A-Za-z0-9_]*(?::[^%\\n]*)?)%")

    // MARK: меню

    /// Если в тексте есть строки «MenuName:», это всплывающее меню. Иначе nil.
    static func parseMenu(_ text: String) -> [MenuDef]? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("MenuName:") }) else { return nil }
        var items: [MenuDef] = []
        var label: String?
        var body: [String] = []
        func finish() {
            if let l = label {
                var t = body.joined(separator: "\n")
                while t.hasSuffix("\n") { t.removeLast() }
                // пустой «MenuName:» без текста — заготовка, в меню не показываем
                if !(l.isEmpty && t.isEmpty) {
                    items.append(MenuDef(label: l.isEmpty ? String(t.prefix(40)) : l, text: t))
                }
            }
            label = nil
            body = []
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("MenuName:") {
                finish()
                label = String(t.dropFirst("MenuName:".count)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("MenuBreak:") {
                finish()
                items.append(MenuDef(label: "", text: "", isSeparator: true))
            } else if label != nil {
                body.append(line)
            }
        }
        finish()
        return items
    }

    // MARK: обработка

    func process(_ raw: String, clipboard: String) -> [PasteAction] {
        var body = raw.replacingOccurrences(of: "\r\n", with: "\n")
        for prefix in ["%pastehtml%", "%phtml%"] where body.lowercased().hasPrefix(prefix) {
            body.removeFirst(prefix.count)
            let html = expandToString(body, clipboard: clipboard)
            return html.isEmpty ? [] : [.html(html)]
        }

        var result: [PasteAction] = []
        var chunk: [String] = []
        func flush() {
            if !chunk.isEmpty {
                result += expand(chunk.joined(separator: "\n"), clipboard: clipboard)
                chunk = []
            }
        }
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("run:") {
                flush()
                let target = expandToString(String(t.dropFirst(4)), clipboard: clipboard)
                    .trimmingCharacters(in: .whitespaces)
                if !target.isEmpty { result.append(.run(target)) }
            } else {
                chunk.append(line)
            }
        }
        flush()
        return result
    }

    /// Только текст, без пауз и нажатий (для HTML и run:).
    func expandToString(_ s: String, clipboard: String) -> String {
        expand(s, clipboard: clipboard).compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }

    func expand(_ s: String, clipboard: String) -> [PasteAction] {
        var out: [PasteAction] = []
        var buf = ""
        let ns = s as NSString
        var pos = 0
        for m in Self.tokenRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            buf += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            switch resolve(ns.substring(with: m.range(at: 1)), clipboard: clipboard) {
            case .text(let t)?:
                buf += t
            case let action?:
                if !buf.isEmpty { out.append(.text(buf)); buf = "" }
                out.append(action)
            case nil:
                buf += ns.substring(with: m.range)   // незнакомое — оставляем как есть
            }
            pos = m.range.location + m.range.length
        }
        buf += ns.substring(from: pos)
        if !buf.isEmpty { out.append(.text(buf)) }
        return out
    }

    func resolve(_ token: String, clipboard c: String) -> PasteAction? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let name = parts[0].lowercased()
        let arg = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        switch name {
        case "date": return .text(format(arg ?? dateFormat))
        case "time": return .text(format(arg ?? timeFormat))
        case "datetime": return .text(format(arg ?? "\(dateFormat) \(timeFormat)"))
        case "tab": return .text("\t")
        case "username": return .text(NSUserName())
        case "userprofile", "home": return .text(NSHomeDirectory())
        case "copy_text", "cpy": return .text(c)
        case "copy_text_uc": return .text(c.uppercased())
        case "copy_text_lc": return .text(c.lowercased())
        case "copy_text_ucfirstword": return .text(Self.upperFirst(c))
        case "copy_text_lc_ucfirstword": return .text(Self.upperFirst(c.lowercased()))
        case "copy_text_ucfirstallwords": return .text(Self.upperEachWord(c))
        case "copy_text_lc_ucfirstallwords": return .text(Self.upperEachWord(c.lowercased()))
        case "copy_text_mix_lc_uc": return .text(Self.mixCase(c))
        case "copy_text_escape": return .text(Self.escape(c))
        case "cpy_txt_urlencode": return .text(Self.urlEncode(c))
        default:
            if name.hasPrefix("sleep_"), let n = Int(name.dropFirst(6)), n >= 0 { return .sleep(min(n, 60_000)) }
            if name.hasPrefix("send_"), let k = Self.sendKeys[String(name.dropFirst(5))] { return .key(k) }
            return nil
        }
    }

    private func format(_ f: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = f
        return df.string(from: now)
    }

    // MARK: преобразования буфера

    static func upperFirst(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }) else { return s }
        return s.replacingCharacters(in: i...i, with: String(s[i]).uppercased())
    }

    static func upperEachWord(_ s: String) -> String {
        var out = ""
        var atStart = true
        for ch in s {
            out += atStart ? String(ch).uppercased() : String(ch)
            atStart = ch.isWhitespace || ch.isNewline
        }
        return out
    }

    static func mixCase(_ s: String) -> String {
        var upper = false
        return String(s.map { ch -> String in
            guard ch.isLetter else { return String(ch) }
            defer { upper.toggle() }
            return upper ? String(ch).uppercased() : String(ch).lowercased()
        }.joined())
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    static func urlEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: предпросмотр

    static func describe(_ actions: [PasteAction]) -> String {
        actions.map { a -> String in
            switch a {
            case .text(let t): return t
            case .html(let h): return "[HTML] " + h
            case .sleep(let ms): return "⟨пауза \(ms) мс⟩"
            case .key(let k): return "⟨" + (sendKeys.first { $0.value == k }?.key.capitalized ?? "клавиша \(k)") + "⟩"
            case .run(let r): return "⟨открыть: \(r)⟩"
            case .typeText(let t): return t
            case .backspace(let n): return "⟨стереть \(n)⟩"
            }
        }.joined()
    }
}
