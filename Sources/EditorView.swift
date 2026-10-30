import SwiftUI
import AppKit

struct EditorView: View {
    var openSettings: () -> Void
    @ObservedObject private var store = Store.shared
    @State private var selection: UUID?
    @State private var search = ""
    @State private var confirmDelete = false

    private var filtered: [Entry] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.label.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search)
                || $0.group.localizedCaseInsensitiveContains(search) || $0.abbreviation.localizedCaseInsensitiveContains(search)
        }
    }

    private var groups: [String] {
        var g: [String] = []
        for e in filtered where !g.contains(e.group) { g.append(e.group) }
        return g
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.self) { g in
                    Section(g.isEmpty ? "Без группы" : g) {
                        ForEach(filtered.filter { $0.group == g }) { e in
                            EntryRow(entry: e).tag(e.id)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Поиск")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "Нажми «+», чтобы добавить текст" : "Ничего не найдено")
                        .foregroundStyle(.secondary)
                }
            }
        } detail: {
            if let id = selection, store.entries.contains(where: { $0.id == id }) {
                EntryDetail(entry: binding(id)).id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Выбери текст слева или добавь новый").foregroundStyle(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: add) { Label("Добавить", systemImage: "plus") }.help("Добавить текст")
                Button(action: duplicate) { Label("Копия", systemImage: "plus.square.on.square") }
                    .help("Сделать копию").disabled(selection == nil)
                Button(action: { move(-1) }) { Label("Выше", systemImage: "arrow.up") }
                    .help("Переместить выше").disabled(selection == nil)
                Button(action: { move(1) }) { Label("Ниже", systemImage: "arrow.down") }
                    .help("Переместить ниже").disabled(selection == nil)
                Button(action: { confirmDelete = true }) { Label("Удалить", systemImage: "trash") }
                    .help("Удалить текст").disabled(selection == nil)
                Button(action: openSettings) { Label("Настройки", systemImage: "gearshape") }.help("Настройки")
            }
        }
        .confirmationDialog("Удалить этот текст?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive, action: deleteSelected)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(selectedEntry?.title ?? "")
        }
        .frame(minWidth: 780, minHeight: 480)
        .onAppear { if selection == nil { selection = store.entries.first?.id } }
    }

    private var selectedEntry: Entry? { store.entries.first { $0.id == selection } }

    private func binding(_ id: UUID) -> Binding<Entry> {
        Binding(
            get: { store.entries.first { $0.id == id } ?? Entry() },
            set: { v in if let i = store.entries.firstIndex(where: { $0.id == id }) { store.entries[i] = v } })
    }

    private func add() {
        var e = Entry(label: "Новый текст", text: "")
        e.group = selectedEntry?.group ?? ""
        if let s = selection, let i = store.entries.firstIndex(where: { $0.id == s }) {
            store.entries.insert(e, at: i + 1)
        } else {
            store.entries.append(e)
        }
        search = ""
        selection = e.id
    }

    private func duplicate() {
        guard let s = selection, let i = store.entries.firstIndex(where: { $0.id == s }) else { return }
        var e = store.entries[i]
        e.id = UUID()
        e.label = e.title + " (копия)"
        e.hotkey = nil
        e.abbreviation = ""
        store.entries.insert(e, at: i + 1)
        selection = e.id
    }

    private func move(_ delta: Int) {
        guard let s = selection, let i = store.entries.firstIndex(where: { $0.id == s }) else { return }
        let group = store.entries[i].group
        // ищем соседа в той же группе
        var j = i + delta
        while j >= 0, j < store.entries.count, store.entries[j].group != group { j += delta }
        guard j >= 0, j < store.entries.count else { return }
        store.entries.swapAt(i, j)
    }

    private func deleteSelected() {
        guard let s = selection, let i = store.entries.firstIndex(where: { $0.id == s }) else { return }
        store.entries.remove(at: i)
        selection = store.entries.indices.contains(i) ? store.entries[i].id : store.entries.last?.id
    }
}

struct EntryRow: View {
    var entry: Entry
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).lineLimit(1)
                Text(entry.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !entry.trimmedAbbreviation.isEmpty {
                Text(entry.trimmedAbbreviation).font(.caption.monospaced())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.18)))
                    .help("Автотекст")
            }
            if let hk = entry.hotkey {
                Text(hk.display).font(.caption.monospaced())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            }
        }
        .opacity(entry.enabled ? 1 : 0.45)
    }
}

struct EntryDetail: View {
    @Binding var entry: Entry
    @State private var preview: String?
    @ObservedObject private var store = Store.shared

    private var conflict: String? {
        guard let hk = entry.hotkey else { return nil }
        if hk == store.settings.menuHotkey { return "Эта клавиша уже открывает меню всех текстов" }
        let others = store.entries.filter { $0.id != entry.id && $0.enabled && $0.hotkey == hk }
        guard let o = others.first else { return nil }
        return "Такая же клавиша у «\(o.title)». Сработает тот, что выше в списке (если подходит программа)."
    }

    private var abbreviationWarning: String? {
        let a = entry.trimmedAbbreviation.lowercased()
        guard !a.isEmpty else { return nil }
        if let o = store.entries.first(where: { $0.id != entry.id && $0.enabled && $0.trimmedAbbreviation.lowercased() == a }) {
            return "Такое же сокращение у «\(o.title)». Сработает только один из них."
        }
        if a.count < 3 {
            return "Короткое сокращение может срабатывать случайно. Лучше 3 символа и больше, например «прив» или «;адр»."
        }
        if entry.abbreviationMode == .immediate,
           let o = store.entries.first(where: { $0.id != entry.id && $0.enabled && $0.trimmedAbbreviation.lowercased().hasPrefix(a) && $0.trimmedAbbreviation.count > a.count }) {
            return "«\(o.trimmedAbbreviation)» начинается с этого сокращения, и сработать не успеет. Выбери «после пробела» или другое сокращение."
        }
        return nil
    }

    private var runningApps: [String] {
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current }
            .compactMap(\.localizedName)
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                TextField("Название в меню", text: $entry.label, prompt: Text("если пусто, будет первая строка текста"))
                TextField("Группа", text: $entry.group, prompt: Text("без группы"))
                LabeledContent("Горячая клавиша") {
                    HotkeyRecorder(hotkey: $entry.hotkey)
                }
                if let conflict {
                    Text(conflict).font(.caption).foregroundStyle(.orange)
                }
                TextField("Сокращение (автотекст)", text: $entry.abbreviation, prompt: Text("например, прив"))
                if !entry.trimmedAbbreviation.isEmpty {
                    Picker("Срабатывает", selection: $entry.abbreviationMode) {
                        ForEach(AutotextMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                Text("Набери сокращение в любой программе — оно заменится этим текстом. Регистр букв не важен.")
                    .font(.caption).foregroundStyle(.secondary)
                if let abbreviationWarning {
                    Text(abbreviationWarning).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Только в программах") {
                    HStack {
                        TextField("", text: $entry.apps, prompt: Text("везде"))
                            .labelsHidden()
                        Menu("Добавить") {
                            ForEach(runningApps, id: \.self) { name in
                                Button(name) { appendApp(name) }
                            }
                        }
                        .fixedSize()
                    }
                }
                Text("Через запятую. «!Safari» значит «везде, кроме Safari».")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Включён", isOn: $entry.enabled)
                Toggle("Показывать в меню", isOn: $entry.showInMenu)
            }

            Section("Текст") {
                TextEditor(text: $entry.text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                HStack {
                    Menu("Вставить команду") {
                        ForEach(CommandHelp.all) { c in
                            Button("\(c.token)  —  \(c.help)") { insert(c) }
                        }
                    }
                    .fixedSize()
                    Button("Проверить") { makePreview() }
                    Spacer()
                }
                if let preview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Что будет вставлено:").font(.caption).foregroundStyle(.secondary)
                        Text(preview).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: entry.text) { _, _ in preview = nil }
    }

    private func appendApp(_ name: String) {
        let t = entry.apps.trimmingCharacters(in: .whitespaces)
        entry.apps = t.isEmpty ? name : t + ", " + name
    }

    private func insert(_ c: CommandHelp) {
        if c.onNewLine {
            if !entry.text.isEmpty && !entry.text.hasSuffix("\n") { entry.text += "\n" }
            entry.text += c.token
        } else {
            entry.text += c.token
        }
    }

    private func makePreview() {
        let s = store.settings
        let p = TextProcessor(dateFormat: s.dateFormat, timeFormat: s.timeFormat)
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        if let defs = TextProcessor.parseMenu(entry.text) {
            preview = "Меню из \(defs.filter { !$0.isSeparator }.count) пунктов:\n" + defs.map {
                $0.isSeparator ? "──────" : "• \($0.label): " + TextProcessor.describe(p.process($0.text, clipboard: clip))
            }.joined(separator: "\n")
        } else {
            let r = TextProcessor.describe(p.process(entry.text, clipboard: clip))
            preview = r.isEmpty ? "(ничего)" : r
        }
    }
}

/// Кнопка «нажми сочетание клавиш».
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(recording ? "Нажми сочетание… (Esc — отмена)" : (hotkey?.display ?? "Не задана"))
                    .frame(minWidth: 120)
            }
            .foregroundStyle(recording ? Color.accentColor : Color.primary)
            if hotkey != nil && !recording {
                Button(action: { hotkey = nil }) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help("Убрать клавишу")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        HotkeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = Hotkey.carbonModifiers(from: e.modifierFlags)
            let isF = Hotkey.functionKeys.contains(Int(e.keyCode))
            if e.keyCode == 53 && mods == 0 { stop(); return nil }               // Esc
            let strong = e.modifierFlags.intersection([.command, .control, .option])
            if strong.isEmpty && !isF { NSSound.beep(); return nil }            // нужна ⌘, ⌃ или ⌥ (или F-клавиша)
            hotkey = Hotkey(keyCode: UInt32(e.keyCode), modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotkeyCenter.shared.resume()
        }
    }
}
