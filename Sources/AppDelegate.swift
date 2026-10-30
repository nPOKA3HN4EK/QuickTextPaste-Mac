import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var store: Store { Store.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // вторую копию не запускаем
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
            if let other = others.first {
                other.activate()
                NSApp.terminate(nil)
                return
            }
        }

        setupMainMenu()
        store.load()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "QuickTextPaste")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "QuickTextPaste"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        HotkeyCenter.shared.install()
        HotkeyCenter.shared.onResume = { [weak self] in self?.refreshHotkeys() }
        store.onChange = { [weak self] in
            self?.refreshHotkeys()
            self?.applyWindowLevel()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        AutotextEngine.shared.isBusy = { Paster.shared.busy }
        AutotextEngine.shared.onMatch = { [weak self] m in self?.autotextFired(m) }
        refreshHotkeys()

        if let err = store.loadError {
            let alert = NSAlert()
            alert.messageText = "Не удалось прочитать тексты"
            alert.informativeText = "Файл texts.json не открылся (\(err)).\n\nЧтобы ничего не потерять, программа не будет его менять, пока ты не разберёшься. Копия файла лежит рядом, в той же папке."
            alert.addButton(withTitle: "Открыть папку")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(store.dir) }
        }
        if !Paster.isTrusted { Paster.promptAccessibility() }
        if store.isFirstRun { openEditor() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openEditor()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.writeNow()
    }

    // MARK: горячие клавиши

    @objc private func appActivated(_ note: Notification) {
        AutotextEngine.shared.reset()
        refreshHotkeys()
    }

    /// Регистрируем только клавиши, которые подходят к программе, что сейчас впереди.
    func refreshHotkeys() {
        guard !HotkeyCenter.shared.suspended else { return }
        let front = NSWorkspace.shared.frontmostApplication
        var items: [(Hotkey, () -> Void)] = []
        var used = Set<Hotkey>()
        if let mh = store.settings.menuHotkey {
            used.insert(mh)
            items.append((mh, { [weak self] in self?.showAllTextsMenu() }))
        }
        for e in store.entries where e.enabled {
            guard let hk = e.hotkey, !used.contains(hk), e.matches(front) else { continue }
            used.insert(hk)
            let id = e.id
            items.append((hk, { [weak self] in self?.trigger(id) }))
        }
        let failed = HotkeyCenter.shared.set(items)
        if !failed.isEmpty { NSLog("QuickTextPaste: заняты клавиши \(failed.map(\.display))") }
        refreshAutotext(front)
    }

    // MARK: автотекст

    private func refreshAutotext(_ front: NSRunningApplication?) {
        let engine = AutotextEngine.shared
        // в своём же окне редактора автотекст не срабатывает, иначе сокращение не ввести
        let ours = front?.processIdentifier == NSRunningApplication.current.processIdentifier
        engine.candidates = ours ? [] : store.entries
            .filter { $0.enabled && !$0.trimmedAbbreviation.isEmpty && $0.matches(front) }
            .map { AutotextCandidate(id: $0.id, abbreviation: $0.trimmedAbbreviation, mode: $0.abbreviationMode) }
        let needed = store.settings.autotextEnabled && store.entries.contains { $0.enabled && !$0.trimmedAbbreviation.isEmpty }
        if needed { engine.start() } else { engine.stop() }
    }

    private func autotextFired(_ m: AutotextMatch) {
        guard let e = store.entries.first(where: { $0.id == m.id }) else { return }
        if let defs = TextProcessor.parseMenu(e.text) {
            // стираем сокращение и показываем меню
            Paster.shared.paste("", deleteFirst: m.deleteCount) { [weak self] in
                self?.popUp { menu in self?.addMenuDefs(defs, to: menu) }
            }
            return
        }
        var trailing: [PasteAction] = []
        switch m.delimiter {
        case "\n"?: trailing = [.key(UInt16(kVK_Return))]
        case "\t"?: trailing = [.key(UInt16(kVK_Tab))]
        case let d?: trailing = [.typeText(String(d))]
        case nil: break
        }
        Paster.shared.paste(e.text, deleteFirst: m.deleteCount, trailing: trailing)
    }

    private func trigger(_ id: UUID) {
        guard let e = store.entries.first(where: { $0.id == id }) else { return }
        if let defs = TextProcessor.parseMenu(e.text) {
            popUp { menu in self.addMenuDefs(defs, to: menu) }
        } else {
            Paster.shared.paste(e.text)
        }
    }

    // MARK: всплывающие меню

    private func popUp(_ build: (NSMenu) -> Void) {
        let previous = NSWorkspace.shared.frontmostApplication
        let menu = NSMenu()
        menu.autoenablesItems = false
        build(menu)
        guard !menu.items.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        if let previous, previous != NSRunningApplication.current { previous.activate() }
    }

    private func showAllTextsMenu() {
        popUp { menu in self.fillEntries(into: menu, includeService: false) }
    }

    private func addMenuDefs(_ defs: [MenuDef], to menu: NSMenu) {
        for d in defs {
            if d.isSeparator {
                menu.addItem(.separator())
            } else {
                let item = NSMenuItem(title: d.label, action: #selector(pickText(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = d.text
                item.toolTip = d.text
                menu.addItem(item)
            }
        }
    }

    @objc private func pickText(_ item: NSMenuItem) {
        guard let text = item.representedObject as? String else { return }
        // ждём, пока меню закроется и вернётся окно, куда вставляем
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Paster.shared.paste(text) }
    }

    // MARK: меню в строке сверху

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fillEntries(into: menu, includeService: true)
    }

    private func entryItem(_ e: Entry) -> NSMenuItem {
        var title = e.title
        if let hk = e.hotkey { title += "\t" + hk.display }
        if let defs = TextProcessor.parseMenu(e.text) {
            // без своего действия: подменю macOS назначит сама. Если стереть его после, пункт станет серым
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            addMenuDefs(defs, to: sub)
            item.submenu = sub
            return item
        }
        let item = NSMenuItem(title: title, action: #selector(pickText(_:)), keyEquivalent: "")
        item.target = self
        item.toolTip = e.text
        item.representedObject = e.text
        return item
    }

    private func fillEntries(into menu: NSMenu, includeService: Bool) {
        var list = store.entries.filter { $0.enabled && $0.showInMenu }
        if store.settings.sortMenu {
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        var groupOrder: [String] = []
        for e in list where !e.group.isEmpty && !groupOrder.contains(e.group) { groupOrder.append(e.group) }
        if store.settings.sortMenu { groupOrder.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

        for e in list where e.group.isEmpty { menu.addItem(entryItem(e)) }
        for g in groupOrder {
            let item = NSMenuItem(title: g, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for e in list where e.group == g { sub.addItem(entryItem(e)) }
            item.submenu = sub
            menu.addItem(item)
        }
        if list.isEmpty {
            let empty = NSMenuItem(title: "Текстов пока нет", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        guard includeService else { return }

        menu.addItem(.separator())
        if !Paster.isTrusted {
            let warn = NSMenuItem(title: "⚠️ Дать разрешение «Универсальный доступ»…", action: #selector(askAccess), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        let edit = NSMenuItem(title: "Редактор текстов…", action: #selector(openEditor), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)
        let prefs = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти из QuickTextPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func askAccess() {
        Paster.promptAccessibility()
        Paster.openAccessibilitySettings()
    }

    // MARK: окна

    @objc func openEditor() {
        if editorWindow == nil {
            editorWindow = makeWindow(title: "QuickTextPaste — тексты", size: NSSize(width: 960, height: 620),
                                      autosave: "EditorWindow", view: EditorView(openSettings: { [weak self] in self?.openSettings() }))
        }
        show(editorWindow)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "QuickTextPaste — настройки", size: NSSize(width: 560, height: 640),
                                        autosave: "SettingsWindow", view: SettingsView())
        }
        show(settingsWindow)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, autosave: String, view: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: view)
        w.setContentSize(size)
        w.center()
        w.setFrameAutosaveName(autosave)
        return w
    }

    private func show(_ w: NSWindow?) {
        applyWindowLevel()
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }

    private func applyWindowLevel() {
        let level: NSWindow.Level = store.settings.topmost ? .floating : .normal
        editorWindow?.level = level
        settingsWindow?.level = level
    }

    // главное меню нужно, чтобы в полях работали ⌘C / ⌘V / ⌘Z
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Выйти из QuickTextPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}
