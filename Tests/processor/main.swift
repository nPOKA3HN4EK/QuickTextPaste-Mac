// Тесты обработки команд, меню и настроек. Запуск: ./tests.sh
import Foundation

var fails = 0
func check(_ name: String, _ got: [PasteAction], _ want: [PasteAction]) {
    if got == want { print("OK   \(name)") } else { fails += 1; print("FAIL \(name)\n  got:  \(got)\n  want: \(want)") }
}
func ok(_ name: String, _ cond: Bool) {
    if cond { print("OK   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 27; c.hour = 9; c.minute = 5
let now = Calendar.current.date(from: c)!
let p = TextProcessor(dateFormat: "dd.MM.yyyy", timeFormat: "HH:mm", now: now)

check("простой текст", p.process("Привет", clipboard: ""), [.text("Привет")])
check("дата/время", p.process("%DATE% %TIME%", clipboard: ""), [.text("27.10.2026 09:05")])
check("свой формат", p.process("%DATE:yyyy-MM-dd%", clipboard: ""), [.text("2026-10-27")])
check("проценты не трогаем", p.process("скидка 50% и 30%", clipboard: ""), [.text("скидка 50% и 30%")])
check("незнакомая команда", p.process("%foo_bar%", clipboard: ""), [.text("%foo_bar%")])
check("tab/enter/sleep", p.process("Иван%send_tab%Москва%sleep_150%%send_enter%", clipboard: ""),
      [.text("Иван"), .key(48), .text("Москва"), .sleep(150), .key(36)])
check("буфер uc", p.process("%copy_text_uc%", clipboard: "привет мир"), [.text("ПРИВЕТ МИР")])
check("буфер lc", p.process("%copy_text_lc%", clipboard: "ПРИВЕТ"), [.text("привет")])
check("ucFirstWord", p.process("%copy_text_ucFirstWord%", clipboard: "привет мир"), [.text("Привет мир")])
check("lc_ucFirstAllWords", p.process("%copy_text_lc_ucFirstAllWords%", clipboard: "ПРИВЕТ МИР"), [.text("Привет Мир")])
check("mix", p.process("%copy_text_mix_lc_uc%", clipboard: "перемешку"), [.text("пЕрЕмЕшКу")])
check("escape", p.process("%copy_text_escape%", clipboard: "a\"b\n"), [.text("a\\\"b\\n")])
check("urlencode", p.process("%cpy_txt_urlencode%", clipboard: "кот & пёс"),
      [.text("%D0%BA%D0%BE%D1%82%20%26%20%D0%BF%D1%91%D1%81")])
check("run", p.process("Текст\nrun:https://google.com/?q=%cpy_txt_urlencode%", clipboard: "a b"),
      [.text("Текст"), .run("https://google.com/?q=a%20b")])
check("html", p.process("%pastehtml%<b>%DATE%</b>", clipboard: ""), [.html("<b>27.10.2026</b>")])

let menu = TextProcessor.parseMenu("MenuName:Привет\nПривет!\nКак дела?\nMenuBreak:\nMenuName:Пока\nПока!\n")
ok("меню", menu == [MenuDef(label: "Привет", text: "Привет!\nКак дела?"), MenuDef(label: "", text: "", isSeparator: true),
                    MenuDef(label: "Пока", text: "Пока!")])
ok("не меню", TextProcessor.parseMenu("обычный текст") == nil)
let withEmpty = TextProcessor.parseMenu("MenuName:Утро\nПланы?\n\nMenuName:Вечер\n\n\nMenuName:\n\n")
ok("пустая заготовка MenuName: скрыта", withEmpty?.map(\.label) == ["Утро", "Вечер"])

var s = Settings(); s.menuHotkey = nil
let back = try! JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
ok("снятая клавиша меню не возвращается", back.menuHotkey == nil)
let old = try! JSONDecoder().decode(Settings.self, from: "{\"dateFormat\":\"yyyy\"}".data(using: .utf8)!)
ok("старые настройки читаются", old.dateFormat == "yyyy" && old.restoreClipboard && old.menuHotkey != nil && old.autotextEnabled)

// случайный вариант
let vText = "Привет!\n---\nЗдравствуй!\n  ---  \nДобрый день!\n---\n"
ok("варианты разделяются", TextProcessor.variants(vText) == ["Привет!", "Здравствуй!", "Добрый день!"])
ok("без --- один вариант", TextProcessor.variants("a\n--\nb") == ["a\n--\nb"])
ok("--- внутри строки не разделяет", TextProcessor.variants("a --- b").count == 1)
var picks: [String] = []
for _ in 0..<60 { picks.append(TextProcessor.pickVariant(vText)) }
ok("выпадают все варианты", Set(picks).count == 3)
ok("подряд один и тот же не выпадает", zip(picks, picks.dropFirst()).allSatisfy { $0 != $1 })
ok("обычный текст не меняется", TextProcessor.pickVariant("Привет") == "Привет")

// формы
let fText = "Здравствуйте, %ask:Имя клиента%! Сумма %ask:Сумма% руб. %ask: Имя клиента %, до %DATE%"
ok("вопросы без повторов", TextProcessor.questions(fText) == ["Имя клиента", "Сумма"])
ok("нет вопросов", TextProcessor.questions("%DATE% 50%").isEmpty)
var pf = p; pf.answers = ["Имя клиента": "Анна", "Сумма": "1 500"]
check("ответы подставились", pf.process(fText, clipboard: ""), [.text("Здравствуйте, Анна! Сумма 1 500 руб. Анна, до 27.10.2026")])
check("ответ с % не раскрывается", { var q = p; q.answers = ["X": "%DATE%"]; return q.process("%ask:X%", clipboard: "") }(), [.text("%DATE%")])
check("без ответа видно вопрос", p.process("%ask:Сумма%", clipboard: ""), [.text("[Сумма]")])
check("пустой ask не трогаем", p.process("%ask:%", clipboard: ""), [.text("%ask:%")])

// поиск
let items = [SearchItem(title: "Подпись", text: "С уважением, Иван"),
             SearchItem(title: "Привет", path: "Быстрые ответы", text: "Здравствуйте!"),
             SearchItem(title: "Адрес", text: "Москва, ул. Ёлочная")]
ok("поиск по названию", SearchItem.filter(items, "подп").map(\.title) == ["Подпись"])
ok("поиск по тексту", SearchItem.filter(items, "уважением").map(\.title) == ["Подпись"])
ok("поиск по меню", SearchItem.filter(items, "быстрые").map(\.title) == ["Привет"])
ok("ё = е", SearchItem.filter(items, "елочная").map(\.title) == ["Адрес"])
ok("несколько слов", SearchItem.filter(items, "моск ул").map(\.title) == ["Адрес"])
ok("пустой запрос — всё", SearchItem.filter(items, " ").count == 3)
ok("начало названия первым", SearchItem.filter(items, "п").first?.title == "Подпись")
let s2 = try! JSONDecoder().decode(Settings.self, from: "{}".data(using: .utf8)!)
ok("поиск в меню включён по умолчанию", s2.searchMenu)

// списки: туда и обратно без потерь
let listDefs = [MenuDef(label: "Name?", text: "What's your name?"), MenuDef(label: "", text: "", isSeparator: true),
                MenuDef(label: "Давно подписан", text: "Строка 1\nСтрока 2\n---\nВариант 2")]
ok("список → текст → список", TextProcessor.parseMenu(TextProcessor.menuText(listDefs)) == listDefs)
let userMenu = "MenuName:Планы утро\nDo you have any plans for morning?\n\nMenuName:Планы вечер\n\n\nMenuName:\n\n"
let reparsed = TextProcessor.parseMenu(TextProcessor.menuText(TextProcessor.parseMenu(userMenu)!))
ok("старое меню открывается как список", reparsed == TextProcessor.parseMenu(userMenu))

print(fails == 0 ? "\nВСЕ ТЕСТЫ ПРОШЛИ" : "\nОШИБОК: \(fails)")
exit(fails == 0 ? 0 : 1)
