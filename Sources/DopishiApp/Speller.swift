import AppKit

/// Тонкая обёртка над системным NSSpellChecker (рус/англ словари берутся из системы).
@MainActor
enum Speller {
    private static let tag = NSSpellChecker.uniqueSpellDocumentTag()

    /// Запрещаем NSSpellChecker самому определять язык (иначе тащит системные языки).
    /// Мы всегда передаём явный ru/en. Выполняется один раз при первом обращении.
    private static let configured: Void = {
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = false
    }()

    static func isMisspelled(_ word: String, language: String) -> Bool {
        _ = Self.configured
        guard !word.isEmpty else { return false }
        let r = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: language, wrap: false,
            inSpellDocumentWithTag: tag, wordCount: nil)
        return r.location != NSNotFound
    }

    /// Уверенное исправление слова (iOS-style autocorrect) или nil.
    static func correction(for word: String, language: String) -> String? {
        _ = Self.configured
        let range = NSRange(location: 0, length: (word as NSString).length)
        let fix = NSSpellChecker.shared.correction(
            forWordRange: range, in: word, language: language, inSpellDocumentWithTag: tag)
        guard let fix, fix != word, !fix.isEmpty else { return nil }
        return fix
    }
}
