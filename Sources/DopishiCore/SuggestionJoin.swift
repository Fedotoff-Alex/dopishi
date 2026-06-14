import Foundation

public enum SuggestionJoin {
    /// Нормализует стык контекста и подсказки. Модель часто отдаёт продолжение с ведущим
    /// пробелом. Срезаем ведущие пробелы если:
    ///  - midWord == true: дописываем НЕЗАКОНЧЕННОЕ слово ("велосипе" + " д" -> "велосипед",
    ///    а не "велосипе д"); mid-word определяет вызывающий по словарю (Speller), т.к. по
    ///    контексту "велосипе" и законченное "привет" неразличимы, ИЛИ
    ///  - контекст кончается ПРОБЕЛОМ (новое слово, разделитель уже есть).
    /// Иначе (законченное слово без пробела / пунктуация) пробел-разделитель оставляем.
    /// Так дисплей (GhostOverlay тримит ведущие пробелы) и вставка берут одну строку.
    public static func normalize(_ suggestion: String, after context: String, midWord: Bool = false) -> String {
        if suggestion.first == " " {
            let stripLeading = midWord || context.last == " "
            return stripLeading ? String(suggestion.drop(while: { $0 == " " })) : suggestion
        }
        // Обратный случай: модель начала НОВОЕ слово БЕЗ пробела-разделителя (YandexGPT и др.).
        // Стык буква-буква при midWord=false - вставляем пробел: иначе ghost клеится к слову,
        // а набранный пользователем пробел гасит подсказку (посимвольное расхождение).
        // Дописывание слова сюда не попадает - его ловят midWord/completesFragment.
        if !midWord, let last = context.last, last.isLetter,
           let first = suggestion.first, first.isLetter {
            return " " + suggestion
        }
        return suggestion
    }

    /// Дополнение mid-word эвристики для фрагментов, которые САМИ являются словарными словами
    /// ("при", "про", "за"...): misspelled-эвристика вызывающего на них промахивается, ведущий
    /// пробел модели уходит во вставку - "при" + " ложение" даёт "при ложение".
    /// Ловим по стыку: если первое слово подсказки само по себе НЕ словарное, а склейка
    /// фрагмент+слово - словарная, то пробел - артефакт токенизатора, и его надо срезать.
    /// Контрпример: "о" + " на" не склеиваем - "на" валидное слово, модель начинает новое.
    /// isValidWord инжектится вызывающим (NSSpellChecker живёт в App-таргете).
    public static func completesFragment(_ suggestion: String, after context: String,
                                         isValidWord: (String) -> Bool) -> Bool {
        guard suggestion.first == " " else { return false }
        guard let last = context.last, !WordBoundary.isBoundary(last) else { return false }
        let stripped = suggestion.drop(while: { $0 == " " })
        let first = String(stripped.prefix(while: { !WordBoundary.isBoundary($0) }))
        guard !first.isEmpty else { return false }
        let frag = WordEdit.lastWord(of: context)
        guard !frag.isEmpty else { return false }
        if isValidWord(first) { return false }
        return isValidWord(frag + first)
    }
}
