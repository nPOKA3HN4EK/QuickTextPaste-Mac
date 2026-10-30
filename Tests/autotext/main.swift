// Тесты автотекста и проверка, что файл с текстами читается без потерь.
// Запуск: ./tests.sh (берёт копию твоего texts.json, сам файл не меняет)
import Foundation

var fails = 0
func ok(_ name: String, _ cond: Bool) {
    if cond { print("OK   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

let idA = UUID(), idB = UUID(), idC = UUID()
let cands = [
    AutotextCandidate(id: idA, abbreviation: "прив", mode: .afterDelimiter),
    AutotextCandidate(id: idB, abbreviation: ";адр", mode: .immediate),
    AutotextCandidate(id: idC, abbreviation: "привет2", mode: .afterDelimiter),
]
func typeAll(_ s: String, _ m: inout AutotextMatcher) -> AutotextMatch? {
    var last: AutotextMatch?
    for ch in s { if let r = m.type(ch, candidates: cands) { last = r } }
    return last
}
var m = AutotextMatcher()
ok("после пробела", typeAll("прив ", &m) == AutotextMatch(id: idA, deleteCount: 4, delimiter: " "))
m.reset(); ok("без пробела не срабатывает", typeAll("прив", &m) == nil)
m.reset(); ok("внутри слова не срабатывает", typeAll("сприв ", &m) == nil)
m.reset(); ok("после запятой", typeAll("ну, прив,", &m) == AutotextMatch(id: idA, deleteCount: 4, delimiter: ","))
m.reset(); ok("регистр не важен", typeAll("ПРИВ.", &m) == AutotextMatch(id: idA, deleteCount: 4, delimiter: "."))
m.reset(); ok("сразу", typeAll("x ;адр", &m) == AutotextMatch(id: idB, deleteCount: 3, delimiter: nil))
m.reset(); ok("длинное важнее", typeAll("привет2 ", &m) == AutotextMatch(id: idC, deleteCount: 7, delimiter: " "))
m.reset(); _ = typeAll("приф", &m); m.backspace()
ok("исправление backspace", typeAll("в ", &m) == AutotextMatch(id: idA, deleteCount: 4, delimiter: " "))
m.reset(); _ = typeAll("пр", &m); m.reset()
ok("сброс (мышь/стрелки)", typeAll("ив ", &m) == nil)
m.reset(); ok("Enter как разделитель", typeAll("прив\n", &m) == AutotextMatch(id: idA, deleteCount: 4, delimiter: "\n"))

// настоящие данные: передаётся путь к копии texts.json
if CommandLine.arguments.count > 1 {
    let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let raw = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let rawEntries = raw["entries"] as! [[String: Any]]
    let lib = try! JSONDecoder().decode(Library.self, from: data)
    ok("все тексты прочитались (\(rawEntries.count))", lib.entries.count == rawEntries.count)
    let again = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(lib)) as! [String: Any]
    let againEntries = again["entries"] as! [[String: Any]]
    func same(_ a: Any, _ b: Any?) -> Bool {
        (try? JSONSerialization.data(withJSONObject: ["v": a], options: .sortedKeys)) ==
            (try? JSONSerialization.data(withJSONObject: ["v": b ?? NSNull()], options: .sortedKeys))
    }
    ok("после сохранения все поля те же", zip(rawEntries, againEntries).allSatisfy { a, b in a.allSatisfy { same($0.value, b[$0.key]) } })
    let rs = raw["settings"] as! [String: Any], s2 = again["settings"] as! [String: Any]
    ok("настройки сохранились", rs.allSatisfy { same($0.value, s2[$0.key]) })
}

print(fails == 0 ? "\nВСЕ ТЕСТЫ ПРОШЛИ" : "\nОШИБОК: \(fails)")
exit(fails == 0 ? 0 : 1)
