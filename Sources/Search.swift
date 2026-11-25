import Foundation

/// Строка в окне поиска: один текст или пункт из текста-меню.
struct SearchItem: Equatable {
    var title: String
    var path = ""      // группа › меню, откуда пункт
    var text: String
    var hotkey = ""

    /// Все слова запроса должны найтись в названии, пути или тексте. Регистр и ё/е не важны.
    func matches(_ query: String) -> Bool {
        let words = Self.fold(query).split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hay = Self.fold(title + " " + path + " " + text)
        return words.allSatisfy { hay.contains($0) }
    }

    static func filter(_ items: [SearchItem], _ query: String) -> [SearchItem] {
        let found = items.filter { $0.matches(query) }
        let q = fold(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return found }
        // сначала те, у кого совпало начало названия
        return found.filter { fold($0.title).hasPrefix(q) } + found.filter { !fold($0.title).hasPrefix(q) }
    }

    private static func fold(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }
}
