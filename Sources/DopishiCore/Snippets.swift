import Foundation

/// Триггер ":name" в конце набора - общий для эмодзи (":fire") и сниппетов (":sig").
/// ":" принимается в начале текста или после пробела/переноса (не триггерим "http://", "10:30").
public enum ColonTrigger {
    /// (token: ":name", name: "name") или nil.
    public static func token(in prefix: String) -> (token: String, name: String)? {
        guard let colonIdx = prefix.lastIndex(of: ":") else { return nil }
        let after = prefix[prefix.index(after: colonIdx)...]
        guard !after.isEmpty,
              after.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        if colonIdx > prefix.startIndex {
            let before = prefix[prefix.index(before: colonIdx)]
            guard before == " " || before == "\n" || before == "\t" else { return nil }
        }
        let name = String(after)
        return (token: ":" + name, name: name)
    }
}

/// Пользовательские сниппеты (UX-05): ":sig" -> подпись, ":addr" -> адрес. Раскрываются по Tab
/// тем же механизмом, что эмодзи. Встроенные динамические: ":date" и ":time".
public enum SnippetCatalog {
    /// Парсинг настроек: одна строка = "имя: текст". Имя - буквы/цифры/_, регистр сохраняется,
    /// поиск регистронезависимый. Кривые строки молча пропускаются.
    public static func parse(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let sep = line.firstIndex(of: ":") else { continue }
            let name = line[..<sep].trimmingCharacters(in: .whitespaces)
            let text = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !text.isEmpty,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            result[name.lowercased()] = text
        }
        return result
    }

    /// Раскрытие имени: пользовательские важнее встроенных; ":date"/":time" - динамические.
    public static func expansion(name: String, custom: [String: String], now: Date = Date()) -> String? {
        if let t = custom[name.lowercased()] { return t }
        switch name.lowercased() {
        case "date":
            let f = DateFormatter()
            f.dateFormat = "dd.MM.yyyy"
            return f.string(from: now)
        case "time":
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: now)
        default:
            return nil
        }
    }
}
