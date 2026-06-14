import Testing
@testable import DopishiCore

@Suite struct KeyboardLayoutTests {
    @Test func enToRu() {
        #expect(KeyboardLayout.enToRussian("ghbdtn") == "привет")
        #expect(KeyboardLayout.enToRussian("vbh") == "мир")
    }
    @Test func ruToEn() {
        #expect(KeyboardLayout.ruToEnglish("привет") == "ghbdtn")
    }
    @Test func keepsCase() {
        #expect(KeyboardLayout.enToRussian("Ghbdtn") == "Привет")
    }
    @Test func passesUnknownThrough() {
        #expect(KeyboardLayout.enToRussian("123") == "123")
    }

    // MARK: - пунктуация и ё (репорт: "запятые и точки остаются после конвертации")

    @Test func convertsWordsWithCommaAndPeriodPositions() {
        // б и ю живут на клавишах , и . - слова с ними обязаны конвертироваться целиком.
        #expect(KeyboardLayout.enToRussian(",eltn") == "будет")
        #expect(KeyboardLayout.enToRussian("k.,jq") == "любой")
        #expect(KeyboardLayout.ruToEnglish("будет") == ",eltn")
    }

    @Test func convertsShiftedPunctuation() {
        // "?" на RU-раскладке - запятая (Shift+/), "ё" - на тильде.
        #expect(KeyboardLayout.enToRussian("ghbdtn?") == "привет,")
        #expect(KeyboardLayout.enToRussian("xnj`") == "чтоё")
        #expect(KeyboardLayout.enToRussian("`;") == "ёж")
        #expect(KeyboardLayout.ruToEnglish("привет,") == "ghbdtn?")
    }

    @Test func trailingSlashBecomesPeriod() {
        // RU-точка живёт на /-клавише.
        #expect(KeyboardLayout.enToRussian("ghbdtn/") == "привет.")
    }
}
