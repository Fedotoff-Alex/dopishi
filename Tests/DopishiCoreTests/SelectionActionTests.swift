import Testing
@testable import DopishiCore

@Suite struct SelectionActionTests {
    @Test func allActionsHaveStableMenuTitleIds() {
        // D-11/Open Q3: menuTitle отдаёт стабильный id (App локализует через L.tr), не русский текст.
        for a in SelectionAction.allCases {
            #expect(!a.menuTitle.isEmpty)
            #expect(a.menuTitle.hasPrefix("selection.action."))
        }
    }
    @Test func promptEmbedsText() {
        let p = SelectionAction.fix.prompt(for: "превет мир")
        #expect(p.contains("превет мир"))
        #expect(p.contains("Задание:"))
        #expect(p.hasSuffix("Итоговый текст:\n"))
    }
    @Test func translateDirectionByScript() {
        #expect(SelectionAction.translate.prompt(for: "привет").contains("английский"))
        #expect(SelectionAction.translate.prompt(for: "hello").contains("русский"))
    }
    @Test func cleanResultTrimsAndCutsChatter() {
        #expect(SelectionAction.cleanResult("  привет мир  \n\nПояснение: я исправил", originalHadNewlines: false) == "привет мир")
        // Многострочный оригинал - пустые строки внутри результата законны.
        #expect(SelectionAction.cleanResult("абзац один\n\nабзац два", originalHadNewlines: true) == "абзац один\n\nабзац два")
    }
    @Test func cleanResultStripsWrappingQuotes() {
        #expect(SelectionAction.cleanResult("«привет, мир»", originalHadNewlines: false) == "привет, мир")
        #expect(SelectionAction.cleanResult("\"hello\"", originalHadNewlines: false) == "hello")
        // Кавычка только с одной стороны - не трогаем.
        #expect(SelectionAction.cleanResult("\"hello", originalHadNewlines: false) == "\"hello")
    }
}
