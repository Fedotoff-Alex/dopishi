import Foundation

public enum WordBoundary {
    /// Символ завершает слово (пробелы и пунктуация, кроме дефиса/апострофа внутри слов).
    public static func isBoundary(_ ch: Character) -> Bool {
        if ch == "-" || ch == "'" { return false }
        return ch.isWhitespace || ch.isPunctuation || ch.isSymbol
    }

    /// Клавиши QWERTY, на которых в ЙЦУКЕН лежат БУКВЫ (а не пунктуация): ;=ж ,=б .=ю [=х ]=ъ `=ё.
    /// Когда русское слово набирают в EN-раскладке, эти символы прилетают КАК ПУНКТУАЦИЯ
    /// (NSEvent.characters в активной раскладке), но смыслово они - буквы внутри слова.
    /// Апостроф (э) и слэш (RU-точка/запятая) сюда НЕ входят: ' уже не граница (isBoundary),
    /// а / на границе - это намеренная RU-точка (boundaryForSwitch), слово на ней завершается.
    private static let layoutLetterPunct: Set<Character> = [";", ",", ".", "[", "]", "`"]

    /// Граничный символ - на самом деле БУКВА ЙЦУКЕН внутри слова, набранного в EN-раскладке?
    /// True, когда последний символ text - одна из клавиш-букв (;,.[]\`) И токен ПЕРЕД ним
    /// латинский (mis-layout: печатают русское в английской раскладке). Тогда слово НЕ
    /// завершилось - набор продолжается, и целый токен (ghjljk;b) дойдёт до tryTokenLayout
    /// на реальном пробеле, конвертируясь в «продолжи» вместо разрыва на «продол;и».
    ///
    /// Гейт по латинскому префиксу различает mis-layout от настоящей пунктуации:
    ///  - «ghjljk;» (латиница + ;) -> mislayout, НЕ граница (слово «продолжи» продолжается)
    ///  - «привет,» (кириллица + ,) -> настоящая запятая, граница (слово завершено)
    ///  - «,eltn» / «,» (нет латинского префикса) -> граница (запятая в начале / одна)
    public static func endsMislayoutToken(_ text: String) -> Bool {
        guard let last = text.last, layoutLetterPunct.contains(last) else { return false }
        // Префикс = символы перед границей, до ближайшего пробельного или предыдущей границы-БУКВЫ.
        // Берём подряд идущие латинские буквы (и сами клавиши-буквы) непосредственно перед last.
        var prefix: [Character] = []
        for ch in text.dropLast().reversed() {
            if ch.isWhitespace { break }
            prefix.insert(ch, at: 0)
            // Дальше границы, которая НЕ клавиша-буква (напр. реальный пробел уже отсёкся выше),
            // не уходим - но клавиши-буквы и латиницу собираем.
            if !(ch.isLetter || layoutLetterPunct.contains(ch)) { break }
        }
        // Нужна хотя бы одна латинская буква в префиксе (иначе это пунктуация, не mislayout-слово).
        return prefix.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
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

    /// Контекстно-зависимое решение (Punto-стиль). Чистая словарная эвристика выше слепа к
    /// двум кейсам коротких слов: (A) однобуквенные; (B) латиница, которую англ. словарь
    /// считает «словом» (vs=«versus», pf, bp) - тогда asTypedIsWord=true глушит свитч, хотя
    /// человек писал русский предлог. Лечим контекстом: язык соседнего текста (предыдущее
    /// слово) задаёт намерение.
    /// - contextScript: доминирующий скрипт текста ПЕРЕД токеном (.neutral если контекста нет).
    /// - targetScript: язык, в который конвертирует кандидат (ru -> .cyrillic, en -> .latin).
    public static func shouldSwitch(asTypedIsWord: Bool, transliteratedIsWord: Bool,
                                    contextScript: Script, targetScript: Script) -> Bool {
        if contextScript != .neutral {
            // Контекст на языке конверсии (пишем по-русски, токен вышел латиницей): доверяем
            // контексту - конвертим, если транслит словарный. Перебивает ложный asTypedIsWord
            // и допускает 1 букву (в/с/к/о/у...).
            if contextScript == targetScript { return transliteratedIsWord }
            // Контекст на ДРУГОМ языке (пишем по-английски): не трогаем (vs/pf остаются).
            return false
        }
        // Контекста нет (начало строки) - прежняя словарная эвристика.
        return !asTypedIsWord && transliteratedIsWord
    }
}
