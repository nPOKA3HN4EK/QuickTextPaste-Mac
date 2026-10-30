import AppKit
import Carbon.HIToolbox

struct AutotextCandidate {
    var id: UUID
    var abbreviation: String
    var mode: AutotextMode
}

struct AutotextMatch: Equatable {
    var id: UUID
    /// Сколько уже набранных символов стереть в программе.
    var deleteCount: Int
    /// Разделитель, на котором сработало (его нужно вернуть после текста).
    var delimiter: Character?
}

/// Помнит последние набранные символы и ищет в их конце сокращение.
struct AutotextMatcher {
    private(set) var buffer: [Character] = []
    private let limit = 100

    static let delimiters: Set<Character> = [" ", "\n", "\t", ".", ",", "!", "?", ";", ":", "(", ")", "\"", "'", "«", "»", "-"]

    mutating func reset() { buffer.removeAll() }

    mutating func backspace() { if !buffer.isEmpty { buffer.removeLast() } }

    /// Вызывается на каждый набранный символ. Если сработало — возвращает совпадение,
    /// а сам символ в программу пропускать не нужно.
    mutating func type(_ ch: Character, candidates: [AutotextCandidate]) -> AutotextMatch? {
        let sorted = candidates.filter { !$0.abbreviation.isEmpty }
            .sorted { $0.abbreviation.count > $1.abbreviation.count }

        if Self.delimiters.contains(ch) {
            for c in sorted where c.mode == .afterDelimiter {
                if endsWithWord(c.abbreviation, in: buffer) {
                    reset()
                    return AutotextMatch(id: c.id, deleteCount: c.abbreviation.count, delimiter: ch)
                }
            }
        }

        buffer.append(ch)
        if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }

        for c in sorted where c.mode == .immediate {
            if endsWithWord(c.abbreviation, in: buffer) {
                reset()
                // последний символ мы не пропустили в программу, его стирать не надо
                return AutotextMatch(id: c.id, deleteCount: c.abbreviation.count - 1, delimiter: nil)
            }
        }
        return nil
    }

    /// Буфер кончается на сокращение, и перед ним начало строки или не буква/цифра.
    private func endsWithWord(_ abbr: String, in buf: [Character]) -> Bool {
        let a = Array(abbr.lowercased())
        guard buf.count >= a.count else { return false }
        let tail = buf.suffix(a.count).map { Character($0.lowercased()) }
        guard tail == a else { return false }
        if buf.count == a.count { return true }
        let before = buf[buf.count - a.count - 1]
        return !(before.isLetter || before.isNumber)
    }
}

/// Перехватывает нажатия клавиш во всех программах (нужен «Универсальный доступ»).
final class AutotextEngine {
    static let shared = AutotextEngine()
    /// Метка наших собственных нажатий, чтобы не реагировать на них.
    static let syntheticTag: Int64 = 0x5154_5058

    var candidates: [AutotextCandidate] = []
    var onMatch: ((AutotextMatch) -> Void)?
    var isBusy: () -> Bool = { false }

    private var matcher = AutotextMatcher()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?

    var isRunning: Bool { tap != nil }

    /// Включает перехват. Если разрешения ещё нет — пробует снова каждые 3 секунды.
    func start() {
        guard tap == nil else { return }
        if !createTap() {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
                guard let self else { return t.invalidate() }
                if self.createTap() { t.invalidate() }
            }
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        matcher.reset()
    }

    func reset() { matcher.reset() }

    private func createTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, refcon in
            let engine = Unmanaged<AutotextEngine>.fromOpaque(refcon!).takeUnretainedValue()
            return engine.handle(type, event)
        }, userInfo: me) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .keyDown:
            break
        default:
            matcher.reset()   // щелчок мышью: курсор мог переехать
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag { return pass }
        if isBusy() { return pass }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            matcher.reset()
            return pass
        }

        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        var ch: Character?
        switch code {
        case kVK_Delete:
            matcher.backspace()
            return pass
        case kVK_Return, kVK_ANSI_KeypadEnter:
            ch = "\n"
        case kVK_Tab:
            ch = "\t"
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape, kVK_Home, kVK_End,
             kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            matcher.reset()
            return pass
        default:
            var len = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &chars)
            guard len > 0 else { return pass }
            let s = String(utf16CodeUnits: chars, count: len)
            guard s.count == 1, let c = s.first, !c.isNewline, c.asciiValue.map({ $0 >= 32 }) ?? true else {
                matcher.reset()
                return pass
            }
            ch = c
        }

        guard let c = ch, let m = matcher.type(c, candidates: candidates) else { return pass }
        DispatchQueue.main.async { self.onMatch?(m) }
        return nil   // этот символ в программу не пускаем, дальше всё сделает вставка
    }
}
