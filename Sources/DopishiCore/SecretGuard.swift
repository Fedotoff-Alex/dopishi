import Foundation

/// Сквозной secret-guard (MEM-06): единый источник эвристик «похоже на секрет».
/// Применяется на ВСЕХ входах в персистентную память (MemoryStore.record) и в промпт
/// (ContextBuilder.build, ClipboardContentDistiller.prepare) - чтобы секрет (ключ/токен/пароль)
/// физически не попадал ни в один канал хранения. Реакция на найденный секрет - дроп фрагмента
/// целиком (D-04), без маскирования.
///
/// Чистый тип Core: без зависимостей и ресурсов (clean-SwiftPM). Эвристики подобраны под низкий
/// false-positive: префиксы по ГРАНИЦЕ токена (не подстрокой), длинный одиночный токен букв+цифр
/// без URL/путь/email/версия-пунктуации, и `-----BEGIN` (PEM-ключи, многострочно).
public enum SecretGuard {
    /// Похоже ли содержимое на секрет (ключ/токен/пароль) - тогда фрагмент дропается целиком.
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
}
