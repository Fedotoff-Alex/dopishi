import Foundation

/// Действия над выделенным текстом (UX-03): локальная модель переписывает выделение,
/// результат показывается в превью, замена - по Tab, отмена - Esc.
/// Чистая часть: список действий, заголовки меню, сборка промпта. LLM-глю в DopishiLLM.
public enum SelectionAction: CaseIterable, Sendable {
    case fix          // исправить ошибки
    case rewrite      // переписать своими словами
    case shorten      // сократить
    case expand       // расширить
    case translate    // перевести (направление по алфавиту текста)
    case toneFormal   // деловой тон
    case toneFriendly // дружелюбный тон

    public var menuTitle: String {
        switch self {
        case .fix: return "Исправить ошибки"
        case .rewrite: return "Переписать"
        case .shorten: return "Сократить"
        case .expand: return "Расширить"
        case .translate: return "Перевести"
        case .toneFormal: return "Тон: деловой"
        case .toneFriendly: return "Тон: дружелюбный"
        }
    }

    /// Инструкция для модели. Формат «Задание/Текст/Итог» работает в .plain-режиме
    /// на инструкт-моделях (Qwen/T-lite/YandexGPT) без chat-template.
    public func prompt(for text: String) -> String {
        let task: String
        switch self {
        case .fix:
            task = "Исправь орфографические, пунктуационные и грамматические ошибки в тексте. Сохрани смысл, стиль и язык. Верни только исправленный текст без пояснений."
        case .rewrite:
            task = "Перепиши текст другими словами, сохранив смысл и язык. Верни только переписанный текст без пояснений."
        case .shorten:
            task = "Сократи текст, сохранив главный смысл и язык. Верни только сокращённый текст без пояснений."
        case .expand:
            task = "Расширь текст, добавив деталей и сохранив смысл, стиль и язык. Верни только расширенный текст без пояснений."
        case .translate:
            let target = Self.looksCyrillic(text) ? "английский" : "русский"
            task = "Переведи текст на \(target) язык. Верни только перевод без пояснений."
        case .toneFormal:
            task = "Перепиши текст в деловом, формальном тоне, сохранив смысл и язык. Верни только итоговый текст без пояснений."
        case .toneFriendly:
            task = "Перепиши текст в дружелюбном, неформальном тоне, сохранив смысл и язык. Верни только итоговый текст без пояснений."
        }
        return "Задание: \(task)\n\nТекст:\n\(text)\n\nИтоговый текст:\n"
    }

    /// Очистка ответа модели: убрать обрамляющие пробелы/кавычки, отрезать «пояснения»
    /// после пустой строки (модель в .plain-режиме может продолжить болтать).
    public static func cleanResult(_ raw: String, originalHadNewlines: Bool) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Если оригинал был однострочным - всё после первой пустой строки считаем болтовнёй.
        if !originalHadNewlines, let cut = s.range(of: "\n\n") {
            s = String(s[..<cut.lowerBound])
        }
        // Симметричные обрамляющие кавычки (модель любит цитировать ответ).
        for (l, r) in [("\"", "\""), ("«", "»"), ("“", "”")] {
            if s.hasPrefix(l), s.hasSuffix(r), s.count > l.count + r.count {
                s = String(s.dropFirst(l.count).dropLast(r.count))
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}
