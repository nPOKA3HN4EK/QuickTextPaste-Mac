import Carbon

/// Глобальные горячие клавиши через Carbon (работают во всех программах).
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private(set) var suspended = false
    /// Вызывается после записи новой клавиши, чтобы заново зарегистрировать все.
    var onResume: (() -> Void)?

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotkeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Регистрирует список клавиш. Возвращает те, что занять не удалось.
    @discardableResult
    func set(_ items: [(Hotkey, () -> Void)]) -> [Hotkey] {
        clear()
        guard !suspended else { return [] }
        var failed: [Hotkey] = []
        for (i, item) in items.enumerated() {
            let id = UInt32(i + 1)
            var ref: EventHotKeyRef?
            let hid = EventHotKeyID(signature: OSType(0x5154_5058), id: id) // 'QTPX'
            let st = RegisterEventHotKey(item.0.keyCode, item.0.modifiers, hid, GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let ref {
                refs.append(ref)
                actions[id] = item.1
            } else {
                failed.append(item.0)
            }
        }
        return failed
    }

    func clear() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    /// На время записи новой клавиши отключаем все, иначе нажатие перехватится.
    func suspend() {
        suspended = true
        clear()
    }

    func resume() {
        suspended = false
        onResume?()
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}
