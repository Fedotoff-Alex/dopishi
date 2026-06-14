import Foundation

/// Личный словарь пользователя: слова, которые НЕ нужно считать опечаткой и НЕ предлагать
/// исправлять (имена, проекты, термины, сленг) - как игнор-словарь PuntoSwitcher. Хранится
/// в Settings.customDictionary, проверяется в орфо-пути (spellFix). Локально, приватно.
public enum CustomDictionary {
    /// Нормализация для сравнения: обрезка пробелов + нижний регистр.
    public static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Множество нормализованных слов (O(1)-проверка, без пустых).
    public static func normalizedSet(_ words: [String]) -> Set<String> {
        Set(words.map(normalize).filter { !$0.isEmpty })
    }

    /// Слово в личном словаре (нечувствительно к регистру/пробелам).
    public static func contains(_ word: String, in set: Set<String>) -> Bool {
        let n = normalize(word)
        return !n.isEmpty && set.contains(n)
    }
}
