import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var store = Store.shared
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var trusted = Paster.isTrusted
    @State private var message: String?

    private var sample: String {
        let p = TextProcessor(dateFormat: store.settings.dateFormat, timeFormat: store.settings.timeFormat)
        return p.expandToString("%DATE%  %TIME%", clipboard: "")
    }

    var body: some View {
        Form {
            Section("Вставка") {
                Toggle("Возвращать старое содержимое буфера после вставки", isOn: $store.settings.restoreClipboard)
                Stepper("Пауза после вставки: \(store.settings.pasteDelayMs) мс",
                        value: $store.settings.pasteDelayMs, in: 20...1000, step: 20)
                Text("Если в какой-то программе вставляется не то или с опозданием, увеличь паузу.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Меню всех текстов") {
                    HotkeyRecorder(hotkey: $store.settings.menuHotkey)
                }
            }

            Section("Дата и время") {
                TextField("Формат даты (%DATE%)", text: $store.settings.dateFormat)
                TextField("Формат времени (%TIME%)", text: $store.settings.timeFormat)
                LabeledContent("Сейчас получится", value: sample)
                Text("dd — день, MM — месяц, yyyy — год, HH — часы, mm — минуты, ss — секунды, EEEE — день недели.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Окна и меню") {
                Toggle("Окна поверх остальных", isOn: $store.settings.topmost)
                Toggle("Сортировать меню по алфавиту", isOn: $store.settings.sortMenu)
                Toggle("Запускать при входе в систему", isOn: $loginOn)
                    .onChange(of: loginOn) { _, on in setLogin(on) }
            }

            Section("Данные") {
                Toggle("Раз в день делать резервную копию", isOn: $store.settings.backupDaily)
                HStack {
                    Button("Экспорт…", action: exportFile)
                    Button("Импорт…", action: importFile)
                    Button("Открыть папку с данными") { NSWorkspace.shared.open(store.dir) }
                }
                Text("Импорт добавляет тексты к текущим, ничего не заменяя.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Разрешения") {
                LabeledContent("Универсальный доступ") {
                    Text(trusted ? "✅ есть" : "❌ нет").foregroundStyle(trusted ? .green : .red)
                }
                HStack {
                    Button("Открыть настройки macOS") {
                        Paster.promptAccessibility()
                        Paster.openAccessibilitySettings()
                    }
                    Button("Проверить ещё раз") { trusted = Paster.isTrusted }
                }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { trusted = Paster.isTrusted }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "Не получилось изменить автозапуск: \(error.localizedDescription). Перенеси программу в «Программы» и попробуй снова."
            loginOn = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "QuickTextPaste-\(Store.stamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "Сохранено: \(url.path)"
        } catch {
            message = "Ошибка экспорта: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try store.importFile(url)
            message = "Добавлено текстов: \(n)"
        } catch {
            message = "Не удалось прочитать файл: \(error.localizedDescription)"
        }
    }
}
