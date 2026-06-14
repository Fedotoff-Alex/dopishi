import Foundation

/// План замены для орфо-исправления зелёным призраком. Чистая структурная часть:
/// решает ЧТО показать, сколько символов удалить назад и что вставить, по тексту до
/// каретки и инжектированной функции орфо-исправления (слово -> уверенный fix или nil).
/// NSSpellChecker-глю живёт в SuggestionController, здесь его нет (тестируемость).
public enum CorrectionPlan {
    public struct Fix: Equatable {
        public let display: String   // что рисуем зелёным призраком
        public let insert: String    // что вставить вместо удалённого (с сохранением хвостовых пробелов)
        public let deleteCount: Int  // сколько графем удалить назад (Backspace) от каретки

        public init(display: String, insert: String, deleteCount: Int) {
            self.display = display
            self.insert = insert
            self.deleteCount = deleteCount
        }
    }

    /// Вернуть план или nil. Два случая:
    /// 1) мид-слово (каретка прямо после слова, без хвостовой границы) - чиним текущее слово;
    /// 2) только что завершённое слово (каретка после слова + хвостовые ПРОБЕЛЫ/табы) - чиним
    ///    прошлое слово, удаляя слово+хвост и вставляя fix+тот же хвост. Перенос строки хвостом
    ///    НЕ считаем (слово ушло на прошлую строку - туда не лезем).
    public static func plan(for prefix: String, spellFix: (String) -> String?) -> Fix? {
        guard let last = prefix.last else { return nil }

        if !WordBoundary.isBoundary(last) {
            let word = WordEdit.lastWord(of: prefix)
            guard !word.isEmpty, let fix = spellFix(word) else { return nil }
            return Fix(display: fix, insert: fix, deleteCount: word.count)
        }

        if last == " " || last == "\t" {
            let (word, trailing) = WordEdit.lastSpaceTokenWithTrailing(of: prefix)
            guard !word.isEmpty, let fix = spellFix(word) else { return nil }
            return Fix(display: fix, insert: fix + trailing, deleteCount: word.count + trailing.count)
        }

        return nil
    }
}
