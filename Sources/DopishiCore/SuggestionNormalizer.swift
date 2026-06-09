import Foundation

/// Консервативная чистка сырого вывода LLM перед показом подсказки.
/// Убирает служебные токены, reasoning-блоки и метки-заголовки. Обычный текст
/// (включая ведущий пробел, важный для стыка) не трогает.
public enum SuggestionNormalizer {
    public static func normalize(_ raw: String) -> String {
        var s = raw
        // reasoning-блоки <think>...</think> (до удаления одиночных тегов)
        s = s.replacingOccurrences(
            of: "(?s)<think>.*?</think>", with: "", options: .regularExpression)
        // служебные токены вида <|im_start|>, <|endoftext|>, <|assistant|>
        s = s.replacingOccurrences(
            of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
        // Gemma turn tokens иногда всплывают при raw `.plain` prompt с chat-разметкой.
        s = s.replacingOccurrences(
            of: "<start_of_turn>\\s*(user|model)?|<end_of_turn>",
            with: "", options: [.regularExpression, .caseInsensitive])
        // метки-заголовки в начале (Task:, Continuation:, Answer:, Output:, Completion:)
        s = s.replacingOccurrences(
            of: "^\\s*(Task|Continuation|Answer|Output|Completion)\\s*:\\s*",
            with: "", options: [.regularExpression, .caseInsensitive])
        // Горизонтальные пробелы (неразрывный U+00A0 и пр.) приводим к обычному и схлопываем
        // повторы: иначе пословный приём по Tab не разделит слова (вставит фразу целиком),
        // а между словами появляются по 2 пробела.
        s = s.replacingOccurrences(of: "\\h+", with: " ", options: .regularExpression)
        return s
    }
}
