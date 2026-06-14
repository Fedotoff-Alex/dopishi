import Foundation

/// Решает, должна ли английская орфо-коррекция УСТУПИТЬ конвертации раскладки.
///
/// Набор русского слова в английской раскладке ("ghbdtn" = физические клавиши «привет»)
/// даёт латиницу, которую NSSpellChecker «исправляет» в английскую чушь. Если латинское
/// слово конвертится в ВАЛИДНОЕ русское слово - это набор в чужой раскладке, а не опечатка:
/// английскую коррекцию подавляем, а конвертацию раскладки (Punto, на пробеле/тапе Option)
/// не трогаем - она и сделает "ghbdtn" -> "привет".
public enum LayoutAwareCorrection {
    /// true -> подавить английскую орфо-коррекцию (слово - mis-layout русского).
    /// isValidRussian инжектится вызывающим (NSSpellChecker живёт в App-таргете):
    /// слово -> валидно ли оно как русское.
    public static func looksLikeMislayoutRussian(_ word: String,
                                                 isValidRussian: (String) -> Bool) -> Bool {
        guard TextScriptDetector.dominant(of: word) == .latin else { return false }
        let converted = KeyboardLayout.enToRussian(word)
        guard converted != word else { return false }   // ничего не сконвертилось
        return isValidRussian(converted)
    }
}
