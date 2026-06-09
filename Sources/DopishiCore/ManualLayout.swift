import Foundation

/// Принудительная (Punto-стиль) конверсия слова в противоположную раскладку.
/// В отличие от авто-режима НЕ проверяет валидность словарём - пользователь сам попросил.
public enum ManualLayout {
    /// (заменитель, целевой язык раскладки) или nil, если конвертировать нечего.
    public static func convert(_ word: String) -> (replacement: String, language: String)? {
        // Не конвертируем ОДИНОЧНЫЙ символ: одиночная замена (напр. "б"->",") почти всегда
        // непреднамеренна - стрей-тап Option или кривое AX-выделение в Electron - и даёт сюрприз
        // вида "добрался"->"до,рался". Раскладку переключают для слов, а не для одной клавиши
        // (авто-свитч в wordCompleted уже требует >=2 символов; выравниваем ручной с ним).
        guard word.count >= 2 else { return nil }
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
