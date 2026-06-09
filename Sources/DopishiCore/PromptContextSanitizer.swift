import Foundation

/// Санитайзер вспомогательного контекста промпта (OCR-окружение, буфер) - того, что НЕ из самого
/// поля ввода. OCR/буфер часто содержат терминальные разделители, ANSI-escape, рамки, стрелки и
/// прочие prompt-shaped символы; малая локальная модель может скопировать их в вывод. Поэтому -
/// чистая детерминированная Foundation-логика (без AppKit/Vision), легко тестируемая.
///
/// Собственная реализация по поведенческой спецификации (см. PromptContextSanitizerTests). Идеи
/// (ANSI-strip, allowlist символов, отбраковка OCR-шумовых токенов по гласным/регистру/длине) -
/// общеизвестные приёмы; словарей-эвристик нет.
public enum PromptContextSanitizer {
    private static let ansiEscapePattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
    private static let allowedCharacters = CharacterSet.alphanumerics
        .union(.whitespacesAndNewlines)
        .union(CharacterSet(charactersIn: "@."))

    /// Prompt-safe текст: только буквы, цифры, пробелы, `@` и `.`. Запрещённые скаляры -> ПРОБЕЛ
    /// (не удаляются: `raw-output` -> `raw output`, границы слов целы). Построчно схлопывает
    /// повторные пробелы, выбрасывает пустые строки, опц. обрезает по длине.
    public static func sanitize(_ rawText: String, maxCharacters: Int? = nil) -> String {
        let noANSI = rawText.replacingOccurrences(of: ansiEscapePattern, with: " ",
                                                  options: .regularExpression)
        let mapped = String(String.UnicodeScalarView(
            noANSI.unicodeScalars.map { allowedCharacters.contains($0) ? $0 : " " }))
        let lines = mapped.components(separatedBy: .newlines)
            .map { collapseSpaces($0) }
            .filter { !$0.isEmpty }
        let joined = lines.joined(separator: "\n")
        let bounded = maxCharacters.map { String(joined.prefix($0)) } ?? joined
        return bounded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Строже для OCR: поверх sanitize построчно роняет строки-шум (галлюцинации Vision: блобы,
    /// числовой UI-хром, повтор-глифы), держит реальную прозу любого языка.
    public static func sanitizeOCR(_ rawText: String, maxCharacters: Int? = nil) -> String {
        let base = sanitize(rawText, maxCharacters: nil)
        let lines = base.components(separatedBy: .newlines).compactMap { keepLine($0) }
        let joined = lines.joined(separator: "\n")
        let bounded = maxCharacters.map { String(joined.prefix($0)) } ?? joined
        return bounded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Лоуэркейс-токены длиной >= minimumLength (разрез по не-alphanumeric). Для relevance/дистилляции.
    public static func significantTokens(from text: String, minimumLength: Int = 3) -> Set<String> {
        Set(text.lowercased().components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= minimumLength })
    }

    public static func containsAlphanumericSignal(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func collapseSpaces(_ line: String) -> String {
        line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OCR-шум

    /// Держим строку, если >= половины токенов содержательны И есть хоть один «сильный» токен.
    private static func keepLine(_ line: String) -> String? {
        let tokens = line.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        let assessed = tokens.map { ($0, assess($0)) }
        let kept = assessed.filter { $0.1.keep }.map { $0.0 }
        guard kept.count * 2 >= tokens.count else { return nil }
        guard assessed.contains(where: { $0.1.keep && $0.1.strong }) else { return nil }
        let result = kept.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Оценка токена: (держать ли, сильный ли сигнал). Порядок важен.
    private static func assess(_ t: String) -> (keep: Bool, strong: Bool) {
        if t.allSatisfy(\.isNumber) { return (false, false) }              // числовой UI-хром (50, 424)
        if isEmailLike(t) || isFileOrDomainLike(t) { return (true, true) } // email/файл/домен
        if isRepeatedGlyph(t) { return (false, false) }                   // повтор одного символа
        if containsNonASCIILetter(t) { return (true, true) }              // CJK/кириллица/диакритика
        if isShortMixedCaseBlob(t) { return (false, false) }              // gLVWrt, bDokE
        if hasASCIIVowel(t) { return (true, true) }                       // нормальное слово/акроним с гласной
        return (false, false)                                             // консонантный блоб (PR, 54tbdbDX)
    }

    private static func containsNonASCIILetter(_ t: String) -> Bool {
        t.unicodeScalars.contains { $0.value > 127 && CharacterSet.letters.contains($0) }
    }
    private static func hasASCIIVowel(_ t: String) -> Bool {
        let vowels = CharacterSet(charactersIn: "aeiouy")
        return t.lowercased().unicodeScalars.contains { vowels.contains($0) }
    }
    private static func isEmailLike(_ t: String) -> Bool {
        let p = t.split(separator: "@", omittingEmptySubsequences: false)
        return p.count == 2 && p[0].contains(where: \.isLetter) && isFileOrDomainLike(String(p[1]))
    }
    private static func isFileOrDomainLike(_ t: String) -> Bool {
        let p = t.split(separator: ".", omittingEmptySubsequences: false)
        return p.count >= 2 && p.allSatisfy { !$0.isEmpty } && p.contains { $0.contains(where: \.isLetter) }
    }
    private static func isRepeatedGlyph(_ t: String) -> Bool {
        let scalars = t.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        guard scalars.count >= 4 else { return false }
        var freq: [UnicodeScalar: Int] = [:]
        for s in scalars { freq[s, default: 0] += 1 }
        return (freq.values.max() ?? 0) * 2 >= scalars.count
    }
    /// Короткий (<=12) токен с буквами обоих регистров и >=2 заглавными (или не с ведущей
    /// заглавной) - типичный OCR-блоб (gLVWrt, bDokE). Длинные camelCase-идентификаторы (>12)
    /// и слова с одной ведущей заглавной (Safari, Dopishi) - НЕ блоб.
    private static func isShortMixedCaseBlob(_ t: String) -> Bool {
        let letters = t.filter(\.isLetter)
        guard t.count <= 12, letters.count >= 4 else { return false }
        let upper = letters.filter(\.isUppercase).count
        let lower = letters.filter(\.isLowercase).count
        guard upper >= 1, lower >= 1 else { return false }
        if upper == 1, letters.first?.isUppercase == true { return false }
        return upper >= 2 || letters.first?.isUppercase != true
    }
}
