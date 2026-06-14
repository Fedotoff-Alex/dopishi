import Testing
@testable import DopishiCore

@Suite struct CorrectionPlanTests {
    // Фейковый словарь: знает только "превет"->"привет". Так тест проверяет СТРУКТУРНУЮ
    // часть (мид-слово / после-пробела + что удалить/вставить), без NSSpellChecker.
    private let fix: (String) -> String? = { $0.lowercased() == "превет" ? "привет" : nil }

    @Test func midWordOffersFix() {
        let p = CorrectionPlan.plan(for: "превет", spellFix: fix)
        #expect(p?.display == "привет")
        #expect(p?.insert == "привет")
        #expect(p?.deleteCount == 6)
    }

    @Test func afterSpaceFixesCompletedWord() {
        // Каретка после "превет " (слово завершено пробелом) - чиним прошлое слово,
        // удаляя слово + пробел и вставляя исправление + тот же пробел.
        let p = CorrectionPlan.plan(for: "превет ", spellFix: fix)
        #expect(p?.display == "привет")
        #expect(p?.insert == "привет ")
        #expect(p?.deleteCount == 7)
    }

    @Test func afterSpaceKeepsEarlierWords() {
        // Только последнее слово трогаем; "Привет," до пробела остаётся.
        let p = CorrectionPlan.plan(for: "Привет, превет ", spellFix: fix)
        #expect(p?.insert == "привет ")
        #expect(p?.deleteCount == 7)
    }

    @Test func newlineIsNotTrailing() {
        // Перенос строки - слово на прошлой строке, туда не лезем.
        #expect(CorrectionPlan.plan(for: "превет\n", spellFix: fix) == nil)
    }

    @Test func noFixNoPlan() {
        #expect(CorrectionPlan.plan(for: "привет", spellFix: fix) == nil)
        #expect(CorrectionPlan.plan(for: "привет ", spellFix: fix) == nil)
    }

    @Test func emptyOrPunctuationOnly() {
        #expect(CorrectionPlan.plan(for: "", spellFix: fix) == nil)
        #expect(CorrectionPlan.plan(for: "!!! ", spellFix: fix) == nil)
    }

    @Test func multipleTrailingSpacesPreserved() {
        let p = CorrectionPlan.plan(for: "превет  ", spellFix: fix)
        #expect(p?.insert == "привет  ")
        #expect(p?.deleteCount == 8)
    }
}
