import Foundation

/// Срезает из начала подсказки слова, которые дублируют хвост контекста.
/// Пример: контекст "я написал", подсказка "написал письмо" -> "письмо".
/// Логика консервативна - берёт максимальное совпадение по folded-словам (до K=6).
public enum EchoPrefixGuard {
    private static let maxContextWords = 6

    /// Срезать echo-префикс из `suggestion` относительно `context`.
    /// Возвращает подсказку без повторённых слов контекста (с сохранением ведущего пробела).
    public static func strip(_ suggestion: String, context: String) -> String {
        guard !suggestion.isEmpty else { return suggestion }

        // Ведущий пробел сохраняем отдельно - он важен для стыка с текстом
        let leadingSpace = suggestion.hasPrefix(" ") ? " " : ""

        // Разбиваем на слова (по пробелу, оставляя пустые - чтобы индексировать позиции)
        let contextWords = context.components(separatedBy: " ").filter { !$0.isEmpty }
        let suggWords = suggestion.components(separatedBy: " ").filter { !$0.isEmpty }

        guard !contextWords.isEmpty, !suggWords.isEmpty else { return suggestion }

        let maxK = min(maxContextWords, min(contextWords.count, suggWords.count))

        // Ищем максимальный K, при котором хвост контекста совпадает с началом подсказки (folded)
        var bestK = 0
        for k in 1...maxK {
            let ctxTail = contextWords.suffix(k).map { TextFold.folded($0) }.joined()
            let sugHead = suggWords.prefix(k).map { TextFold.folded($0) }.joined()
            if ctxTail == sugHead {
                bestK = k
            }
        }

        guard bestK > 0 else { return suggestion }

        // Убираем первые bestK слов из подсказки, восстанавливаем ведущий пробел
        let remaining = Array(suggWords.dropFirst(bestK))
        if remaining.isEmpty { return leadingSpace }
        return leadingSpace + remaining.joined(separator: " ")
    }
}
