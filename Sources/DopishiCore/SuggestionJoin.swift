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
        guard suggestion.first == " " else { return suggestion }
        let stripLeading = midWord || context.last == " "
        return stripLeading ? String(suggestion.drop(while: { $0 == " " })) : suggestion
    }
}
