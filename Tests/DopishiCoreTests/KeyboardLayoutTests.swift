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

    // MARK: - граничная пунктуация при свитче (запрос: «,» «.» в английской раскладке)

    @Test func boundaryKeepsActualPunctuation() {
        // Пользователь набрал реальные , и . как пунктуацию - оставляем (раньше enToRussian
        // делал ","->"б", "."->"ю" -> "приветб"/"приветю").
        #expect(KeyboardLayout.boundaryForSwitch(",", to: "ru") == ",")
        #expect(KeyboardLayout.boundaryForSwitch(".", to: "ru") == ".")
        #expect(KeyboardLayout.boundaryForSwitch(",", to: "en") == ",")
        #expect(KeyboardLayout.boundaryForSwitch(".", to: "en") == ".")
    }

    @Test func boundaryConvertsYtsukenPunctuationPositions() {
        // Позиции пунктуации ЙЦУКЕН при свитче в ru: / -> точка, ? -> запятая.
        #expect(KeyboardLayout.boundaryForSwitch("/", to: "ru") == ".")
        #expect(KeyboardLayout.boundaryForSwitch("?", to: "ru") == ",")
    }

    @Test func boundaryPassesSpaceThrough() {
        #expect(KeyboardLayout.boundaryForSwitch(" ", to: "ru") == " ")
        #expect(KeyboardLayout.boundaryForSwitch(" ", to: "en") == " ")
    }

    // MARK: - числа с разделителями ю/б (запрос: "2ю1" -> "2.1")

    @Test func fixesNumericSeparators() {
        #expect(KeyboardLayout.fixNumericSeparators("2ю1") == "2.1")
        #expect(KeyboardLayout.fixNumericSeparators("10б5") == "10,5")
        #expect(KeyboardLayout.fixNumericSeparators("1ю2ю3") == "1.2.3")
    }

    @Test func numericSeparatorsIgnoresNonNumberTokens() {
        // буквы рядом - не наш случай (это слово, им займётся обычный свитч)
        #expect(KeyboardLayout.fixNumericSeparators("2ю1а") == nil)
        #expect(KeyboardLayout.fixNumericSeparators("ghbdtn") == nil)
        // разделитель на краю - не конвертим (нет цифры с обеих сторон)
        #expect(KeyboardLayout.fixNumericSeparators("2ю") == nil)
        #expect(KeyboardLayout.fixNumericSeparators("ю1") == nil)
        // нет разделителя - нечего чинить
        #expect(KeyboardLayout.fixNumericSeparators("21") == nil)
        // уже точка - не наш вход (нет ю/б)
        #expect(KeyboardLayout.fixNumericSeparators("2.1") == nil)
    }
}
