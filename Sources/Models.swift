import AppKit
import Carbon.HIToolbox

/// Горячая клавиша: код клавиши + модификаторы в формате Carbon (cmdKey, optionKey...).
struct Hotkey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Hotkey.keyName(keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static let functionKeys: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                      kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    private static let specialNames: [Int: String] = {
        var d: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn", kVK_ANSI_KeypadEnter: "Num⌤",
            kVK_ANSI_Keypad0: "Num0", kVK_ANSI_Keypad1: "Num1", kVK_ANSI_Keypad2: "Num2", kVK_ANSI_Keypad3: "Num3",
            kVK_ANSI_Keypad4: "Num4", kVK_ANSI_Keypad5: "Num5", kVK_ANSI_Keypad6: "Num6", kVK_ANSI_Keypad7: "Num7",
            kVK_ANSI_Keypad8: "Num8", kVK_ANSI_Keypad9: "Num9", kVK_ANSI_KeypadPlus: "Num+", kVK_ANSI_KeypadMinus: "Num-",
            kVK_ANSI_KeypadMultiply: "Num*", kVK_ANSI_KeypadDivide: "Num/", kVK_ANSI_KeypadDecimal: "Num.",
        ]
        for (i, k) in functionKeys.enumerated() { d[k] = "F\(i + 1)" }
        return d
    }()

    /// Имя клавиши в латинской раскладке (чтобы при русской раскладке не показывалось «Й» вместо «Q»).
    static func keyName(_ code: UInt32) -> String {
        if let s = specialNames[Int(code)] { return s }
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 4, &len, &chars)
        }
        guard status == noErr, len > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: len).uppercased()
    }
}

/// Когда срабатывает автотекст.
enum AutotextMode: String, Codable, CaseIterable, Identifiable {
    case afterDelimiter   // после пробела, Enter или знака препинания
    case immediate        // сразу после последней буквы
    var id: String { rawValue }
    var title: String {
        switch self {
        case .afterDelimiter: return "После пробела или знака препинания"
        case .immediate: return "Сразу после последней буквы"
        }
    }
}

/// Один текст из списка.
struct Entry: Codable, Identifiable, Equatable {
    var id = UUID()
    var label = ""
    var text = ""
    var group = ""
    var hotkey: Hotkey?
    /// Программы через запятую. Пусто = везде. «!Имя» = везде, кроме этой программы.
    var apps = ""
    var enabled = true
    var showInMenu = true
    /// Автотекст: набираешь это сокращение — оно заменяется текстом. Пусто = выключено.
    var abbreviation = ""
    var abbreviationMode = AutotextMode.afterDelimiter

    init(label: String = "", text: String = "", group: String = "", hotkey: Hotkey? = nil, apps: String = "") {
        self.label = label
        self.text = text
        self.group = group
        self.hotkey = hotkey
        self.apps = apps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        apps = try c.decodeIfPresent(String.self, forKey: .apps) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showInMenu = try c.decodeIfPresent(Bool.self, forKey: .showInMenu) ?? true
        abbreviation = try c.decodeIfPresent(String.self, forKey: .abbreviation) ?? ""
        abbreviationMode = (try? c.decodeIfPresent(AutotextMode.self, forKey: .abbreviationMode)) ?? .afterDelimiter
    }

    var trimmedAbbreviation: String { abbreviation.trimmingCharacters(in: .whitespacesAndNewlines) }

    var title: String {
        let l = label.trimmingCharacters(in: .whitespaces)
        if !l.isEmpty { return l }
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let t = first.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "(пустой текст)" }
        return t.count > 40 ? String(t.prefix(40)) + "…" : t
    }

    var appList: [String] {
        apps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    func matches(_ app: NSRunningApplication?) -> Bool {
        let list = appList
        if list.isEmpty { return true }
        let names = [app?.localizedName, app?.bundleIdentifier, app?.executableURL?.lastPathComponent]
            .compactMap { $0?.lowercased() }
        let exclude = list.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }
        let include = list.filter { !$0.hasPrefix("!") }
        if exclude.contains(where: names.contains) { return false }
        return include.isEmpty || include.contains(where: names.contains)
    }

    static var samples: [Entry] {
        let co = UInt32(controlKey | optionKey)
        return [
            Entry(label: "Подпись", text: "С уважением,\nИван", group: "Примеры",
                  hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: co)),
            Entry(label: "Дата и время", text: "%DATE% %TIME%", group: "Примеры",
                  hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: co)),
            Entry(label: "Буфер ЗАГЛАВНЫМИ", text: "%copy_text_uc%", group: "Примеры",
                  hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: co)),
            Entry(label: "Быстрые ответы (меню)",
                  text: "MenuName:Привет\nПривет! Чем могу помочь?\nMenuName:Спасибо\nСпасибо, жду ответа!\nMenuBreak:\nMenuName:Сегодняшняя дата\nСегодня %DATE%",
                  group: "Примеры", hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: co)),
            Entry(label: "Заполнить форму", text: "Иван%send_tab%Москва%send_enter%", group: "Примеры"),
            Entry(label: "Поиск в Google по буферу", text: "run:https://www.google.com/search?q=%cpy_txt_urlencode%", group: "Примеры"),
        ]
    }
}

struct Settings: Codable, Equatable {
    var restoreClipboard = true
    var dateFormat = "dd.MM.yyyy"
    var timeFormat = "HH:mm"
    var topmost = false
    var sortMenu = false
    var backupDaily = true
    var pasteDelayMs = 80
    var menuHotkey: Hotkey? = Hotkey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey))
    var autotextEnabled = true

    enum CodingKeys: String, CodingKey {
        case restoreClipboard, dateFormat, timeFormat, topmost, sortMenu, backupDaily, pasteDelayMs, menuHotkey
        case autotextEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let d = Settings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        dateFormat = try c.decodeIfPresent(String.self, forKey: .dateFormat) ?? d.dateFormat
        timeFormat = try c.decodeIfPresent(String.self, forKey: .timeFormat) ?? d.timeFormat
        topmost = try c.decodeIfPresent(Bool.self, forKey: .topmost) ?? d.topmost
        sortMenu = try c.decodeIfPresent(Bool.self, forKey: .sortMenu) ?? d.sortMenu
        backupDaily = try c.decodeIfPresent(Bool.self, forKey: .backupDaily) ?? d.backupDaily
        pasteDelayMs = try c.decodeIfPresent(Int.self, forKey: .pasteDelayMs) ?? d.pasteDelayMs
        menuHotkey = c.contains(.menuHotkey) ? try c.decodeIfPresent(Hotkey.self, forKey: .menuHotkey) : d.menuHotkey
        autotextEnabled = try c.decodeIfPresent(Bool.self, forKey: .autotextEnabled) ?? d.autotextEnabled
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(restoreClipboard, forKey: .restoreClipboard)
        try c.encode(dateFormat, forKey: .dateFormat)
        try c.encode(timeFormat, forKey: .timeFormat)
        try c.encode(topmost, forKey: .topmost)
        try c.encode(sortMenu, forKey: .sortMenu)
        try c.encode(backupDaily, forKey: .backupDaily)
        try c.encode(pasteDelayMs, forKey: .pasteDelayMs)
        // null пишем явно, чтобы снятая клавиша не вернулась после перезапуска
        try c.encode(menuHotkey, forKey: .menuHotkey)
        try c.encode(autotextEnabled, forKey: .autotextEnabled)
    }
}

struct Library: Codable {
    var entries: [Entry]
    var settings: Settings
}
