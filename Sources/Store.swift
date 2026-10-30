import AppKit

/// Хранит тексты и настройки в ~/Library/Application Support/QuickTextPasteMac/texts.json.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var entries: [Entry] = [] { didSet { changed() } }
    @Published var settings = Settings() { didSet { changed() } }

    private(set) var isFirstRun = false
    /// Файл не прочитался: ничего не записываем, чтобы не затереть тексты пустым списком.
    private(set) var loadError: String?
    var onChange: (() -> Void)?

    private var loading = false
    private var saveWork: DispatchWorkItem?
    private var notifyWork: DispatchWorkItem?

    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuickTextPasteMac", isDirectory: true)
    var file: URL { dir.appendingPathComponent("texts.json") }
    var backupDir: URL { dir.appendingPathComponent("Backups", isDirectory: true) }

    func load() {
        loading = true
        defer { loading = false }
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file) {
            do {
                let lib = try JSONDecoder().decode(Library.self, from: data)
                entries = lib.entries
                settings = lib.settings
            } catch {
                // файл повреждён: сохраняем его копию и больше в него не пишем
                let bad = dir.appendingPathComponent("texts-повреждён-\(Self.stamp()).json")
                try? FileManager.default.copyItem(at: file, to: bad)
                loadError = "\(error)"
                NSLog("QuickTextPaste: не удалось прочитать texts.json: \(error)")
            }
        } else if FileManager.default.fileExists(atPath: file.path) {
            // файл есть, но не открылся (нет доступа и т. п.) — тоже не трогаем
            loadError = "файл texts.json не открывается"
        } else {
            isFirstRun = true
            entries = Entry.samples
            writeNow()
        }
        backupIfNeeded()
    }

    private func changed() {
        guard !loading else { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.writeNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)

        notifyWork?.cancel()
        let n = DispatchWorkItem { [weak self] in self?.onChange?() }
        notifyWork = n
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: n)
    }

    func writeNow() {
        saveWork?.cancel()
        guard loadError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoded().write(to: file, options: .atomic)
        } catch {
            NSLog("QuickTextPaste: не удалось сохранить: \(error)")
        }
    }

    private func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(Library(entries: entries, settings: settings))
    }

    // MARK: резервные копии

    func backupIfNeeded() {
        guard settings.backupDaily, FileManager.default.fileExists(atPath: file.path) else { return }
        let key = "lastBackup"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        let dest = backupDir.appendingPathComponent("texts-\(Self.stamp()).json")
        if (try? FileManager.default.copyItem(at: file, to: dest)) != nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    // MARK: импорт / экспорт

    func export(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    /// Добавляет тексты из файла к текущим (ничего не заменяет). Возвращает, сколько добавлено.
    func importFile(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        let incoming: [Entry]
        if let lib = try? dec.decode(Library.self, from: data) {
            incoming = lib.entries
        } else {
            incoming = try dec.decode([Entry].self, from: data)
        }
        let existing = Set(entries.map(\.id))
        let fresh = incoming.map { e -> Entry in
            var e = e
            if existing.contains(e.id) { e.id = UUID() }
            return e
        }
        entries += fresh
        return fresh.count
    }
}
