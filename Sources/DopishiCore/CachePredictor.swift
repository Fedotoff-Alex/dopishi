import Foundation

/// Мгновенный предиктор (PERF-03): биграммный индекс по принятым подсказкам и памяти.
/// Показывает кандидата ДО ответа LLM; LLM уточняет параллельно и заменяет ghost.
/// Чистая структура без I/O: учится на текстах, предсказывает продолжение после слова.
public struct CachePredictor: Sendable {
    /// последнее слово (lowercased) -> следующее слово (в исходном регистре) -> счётчик
    private var bigrams: [String: [String: Int]] = [:]
    /// Минимум повторов, чтобы предсказывать (одноразовые пары - шум).
    private let minCount: Int

    public init(minCount: Int = 2) {
        self.minCount = minCount
    }

    /// Выучить текст: пары соседних слов. Слова - последовательности не-граничных символов.
    public mutating func learn(_ text: String) {
        let words = Self.words(of: text)
        guard words.count >= 2 else { return }
        for i in 0..<(words.count - 1) {
            let key = words[i].lowercased()
            bigrams[key, default: [:]][words[i + 1], default: 0] += 1
        }
    }

    /// Кандидат-продолжение после префикса (или nil). Только на границе слова (префикс
    /// кончается пробелом) либо сразу после слова - продолжаем ПОСЛЕДНЕЕ завершённое слово.
    /// Жадная цепочка до maxWords, каждое звено должно иметь >= minCount повторов и
    /// уверенное большинство (>= 60% наблюдений после этого слова).
    public func predict(after prefix: String, maxWords: Int = 4) -> String? {
        // Только чистая граница слова (пробел): частичное слово как ключ дало бы ложные
        // предсказания ("при" из "привет" совпало бы с выученным словом "при").
        guard prefix.hasSuffix(" ") else { return nil }
        let trimmed = String(prefix.dropLast())
        guard !trimmed.isEmpty else { return nil }
        let words = Self.words(of: trimmed)
        guard var current = words.last?.lowercased() else { return nil }
        var chain: [String] = []
        for _ in 0..<maxWords {
            guard let nexts = bigrams[current], !nexts.isEmpty else { break }
            let total = nexts.values.reduce(0, +)
            guard let best = nexts.max(by: { $0.value < $1.value }),
                  best.value >= minCount,
                  Double(best.value) >= 0.6 * Double(total) else { break }
            chain.append(best.key)
            current = best.key.lowercased()
        }
        guard !chain.isEmpty else { return nil }
        return " " + chain.joined(separator: " ")
    }

    /// Слова текста (без границ/пунктуации, с сохранением регистра).
    private static func words(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            if WordBoundary.isBoundary(ch) {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Адаптивный бюджет хвоста промпта (PERF-04). KV-safe: статическая голова промпта не меняется,
/// варьируется только динамическая зона (хвост поля).
public enum PromptBudget {
    /// Мид-слово: дописываем слово - свежий локальный контекст важнее длинной истории.
    /// Конец предложения/перенос: начинается новая мысль - контекста нужно больше.
    public static func tailMax(prefix: String, isMidWord: Bool) -> Int {
        if isMidWord { return 240 }
        let tail = prefix.suffix(2)
        if let last = tail.last, last == "\n" { return 600 }
        if let last = prefix.trimmingCharacters(in: .whitespaces).last,
           last == "." || last == "!" || last == "?" {
            return 600
        }
        return 400
    }
}
