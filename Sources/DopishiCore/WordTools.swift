import Foundation

public enum WordBoundary {
    /// Символ завершает слово (пробелы и пунктуация, кроме дефиса/апострофа внутри слов).
    public static func isBoundary(_ ch: Character) -> Bool {
        if ch == "-" || ch == "'" { return false }
        return ch.isWhitespace || ch.isPunctuation || ch.isSymbol
    }
}

public enum WordEdit {
    /// Последнее слово текста (отбросив хвостовые границы), без граничных символов.
    public static func lastWord(of text: String) -> String {
        var chars = Array(text)
        while let last = chars.last, WordBoundary.isBoundary(last) { chars.removeLast() }
        var word: [Character] = []
        while let last = chars.last, !WordBoundary.isBoundary(last) {
            word.insert(last, at: 0)
            chars.removeLast()
        }
        return String(word)
    }

    /// Последний токен, отделённый ТОЛЬКО пробельными символами (пунктуация внутри сохраняется).
    /// Для ручной конверсии раскладки: "ghbdtn,vbh" должно конвертироваться целиком, а не
    /// делиться по запятой (lastWord обрезал бы по пунктуации).
    public static func lastSpaceToken(of text: String) -> String {
        // Токен, ПРИЛЕГАЮЩИЙ к каретке: если перед кареткой пробел - токена нет (пусто).
        var chars = Array(text)
        var token: [Character] = []
        while let last = chars.last, !last.isWhitespace {
            token.insert(last, at: 0)
            chars.removeLast()
        }
        return String(token)
    }

    /// Последний пробел-токен + хвостовой отрезок ПРОБЕЛОВ/ТАБОВ перед кареткой.
    /// Для ручной конверсии раскладки, когда юзер УЖЕ поставил пробел после слова:
    /// "ghbdtn " -> (token: "ghbdtn", trailing: " "). Конверсия применяется к token,
    /// trailing сохраняется при перезаписи. Перенос строки в trailing НЕ собираем (слово
    /// уже на прошлой строке/отправлено) - тогда token будет пуст и конверсия не сработает.
    public static func lastSpaceTokenWithTrailing(of text: String) -> (token: String, trailing: String) {
        var chars = Array(text)
        var trailing: [Character] = []
        while let last = chars.last, last == " " || last == "\t" {
            trailing.insert(last, at: 0)
            chars.removeLast()
        }
        var token: [Character] = []
        while let last = chars.last, !last.isWhitespace {
            token.insert(last, at: 0)
            chars.removeLast()
        }
        return (String(token), String(trailing))
    }
}

public enum LayoutDecision {
    /// Менять раскладку, если как-набрано НЕ валидное слово, а транслит - валидное.
    public static func shouldSwitch(asTypedIsWord: Bool, transliteratedIsWord: Bool) -> Bool {
        !asTypedIsWord && transliteratedIsWord
    }
}
