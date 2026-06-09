import Foundation

/// Дистилляция текста буфера под промпт: для длинного буфера оставляет только строки,
/// пересекающиеся по токенам с тем, что юзер уже набрал (иначе - голова 300 символов).
/// `prepare` - полный конвейер: санитайз prompt-injection -> guard -> дистилляция -> клип 1200.
///
/// Собственная реализация: дистилляция по пересечению токенов строк с префиксом + голова-фолбэк -
/// общеизвестный приём; looksSecret и конвейер prepare - наш дизайн.
public enum ClipboardContentDistiller {
    private static let compactLineThreshold = 3
    private static let headFallbackCharacters = 300
    public static let maxClipboardContextCharacters = 1_200

    /// Полный конвейер подготовки релевантного буфера к вставке в промпт.
    /// Принимает УЖЕ прошедший relevance-фильтр буфер. Возвращает nil, если после санитайза
    /// не осталось буквенно-цифрового сигнала (только символы/пусто).
    public static func prepare(rawRelevant: String, prefix: String,
                               maxChars: Int = maxClipboardContextCharacters) -> String? {
        guard !looksSecret(rawRelevant) else { return nil }   // секреты в промпт не подмешиваем
        let sanitized = PromptContextSanitizer.sanitize(rawRelevant)
        return prepared(sanitized: sanitized, prefix: prefix, maxChars: maxChars)
    }

    /// Дистилляция+клип УЖЕ санитайзнутого текста. sanitize кэшируется по changeCount в ContextProbe,
    /// чтобы не гонять его на каждый keystroke (distill зависит от префикса - его считаем заново).
    public static func prepared(sanitized: String, prefix: String,
                                maxChars: Int = maxClipboardContextCharacters) -> String? {
        guard !sanitized.isEmpty, PromptContextSanitizer.containsAlphanumericSignal(sanitized) else {
            return nil
        }
        let distilled = distill(clipboard: sanitized, prefixText: prefix)
        return clipped(distilled, maxCharacters: maxChars)
    }

    /// Похоже ли содержимое на секрет (ключ/токен/пароль) - тогда НЕ подмешиваем в промпт.
    /// Cotabby этого не делает; добавлено для приватности (буфер - частый транзит секретов).
    /// Эвристики подобраны под низкий false-positive: префиксы по ГРАНИЦЕ токена (не подстрокой),
    /// и длинный одиночный токен букв+цифр без URL/путь/email/версия-пунктуации.
    public static func looksSecret(_ text: String) -> Bool {
        let prefixes = ["sk-", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",
                        "xoxb-", "xoxp-", "xoxa-", "xoxr-", "akia", "eyj"]
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let lower = token.lowercased()
            if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
            if token.count >= 20 {
                let hasLetter = token.contains { $0.isLetter }
                let hasDigit = token.contains { $0.isNumber }
                let hasUrlPunct = token.contains { $0 == "." || $0 == "/" || $0 == "@" || $0 == ":" }
                if hasLetter, hasDigit, !hasUrlPunct { return true }
            }
        }
        if text.contains("-----BEGIN") { return true }   // PEM-ключи (многострочно)
        return false
    }

    /// Дистилляция по строкам. Короткий (<=3 строк) или пустой префикс -> буфер как есть.
    public static func distill(clipboard: String, prefixText: String) -> String {
        let lines = clipboard.components(separatedBy: "\n")
        guard lines.count > compactLineThreshold else { return clipboard }

        let prefixTokens = PromptContextSanitizer.significantTokens(from: prefixText)
        guard !prefixTokens.isEmpty else { return clipboard }

        let relevantLines = lines.filter { line in
            let lineTokens = PromptContextSanitizer.significantTokens(from: line)
            return !lineTokens.isDisjoint(with: prefixTokens)
        }

        if relevantLines.isEmpty {
            return String(clipboard.prefix(headFallbackCharacters))
        }
        return relevantLines.joined(separator: "\n")
    }

    /// Клип до maxCharacters: если длиннее - prefix(max-3), срез хвостовых пробелов, "...".
    private static func clipped(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let head = String(text.prefix(max(0, maxCharacters - 3)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return head + "..."
    }
}
