import Foundation

/// Принудительная (Punto-стиль) конверсия слова в противоположную раскладку.
/// В отличие от авто-режима НЕ проверяет валидность словарём - пользователь сам попросил.
public enum ManualLayout {
    /// (заменитель, целевой язык раскладки) или nil, если конвертировать нечего.
    /// minLength: авто-свитч передаёт 2 (одиночная замена обычно случайна - стрей-тап/кривое
    /// AX-выделение -> сюрприз "добрался"->"до,рался"). Ручной тап - явный жест, передаёт 1,
    /// чтобы конвертировать и одиночные предлоги ("в"/"с"/"к"/"у"/"о").
    public static func convert(_ word: String, minLength: Int = 2) -> (replacement: String, language: String)? {
        guard word.count >= minLength else { return nil }
        switch TextScriptDetector.dominant(of: word) {
        case .latin:
            let r = KeyboardLayout.enToRussian(word)
            return r == word ? nil : (r, "ru")
        case .cyrillic:
            let r = KeyboardLayout.ruToEnglish(word)
            return r == word ? nil : (r, "en")
        case .neutral:
            return nil
        }
    }
}
