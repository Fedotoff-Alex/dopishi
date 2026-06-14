import Testing
@testable import DopishiCore

/// Баг (живой UAT): набор русского в английской раскладке предлагает английскую "коррекцию"
/// в чушь вместо конвертации раскладки. Эти тесты воспроизводят и фиксируют поведение гейта.
@Suite struct LayoutAwareCorrectionTests {
    /// "ghbdtn" в QWERTY -> "привет" в ЙЦУКЕН: латинская коррекция = чушь -> подавляем.
    @Test func mislayoutRussianSuppresses() {
        #expect(KeyboardLayout.enToRussian("ghbdtn") == "привет")
        #expect(LayoutAwareCorrection.looksLikeMislayoutRussian("ghbdtn",
                                                                isValidRussian: { $0 == "привет" }))
    }

    /// Настоящая английская опечатка: конвертация в кириллицу не даёт валидного русского ->
    /// НЕ подавляем (английская коррекция уместна).
    @Test func realEnglishTypoNotSuppressed() {
        #expect(!LayoutAwareCorrection.looksLikeMislayoutRussian("helllo",
                                                                 isValidRussian: { _ in false }))
    }

    /// Кириллица сама по себе - не наш случай (это не латиница, конвертить нечего).
    @Test func cyrillicWordNotMislayout() {
        #expect(!LayoutAwareCorrection.looksLikeMislayoutRussian("превет",
                                                                 isValidRussian: { _ in true }))
    }

    /// Латиница без буквенного содержимого (цифры/символы) - dominant != .latin -> false,
    /// без вызова isValidRussian.
    @Test func nonLetterLatinNotSuppressed() {
        var called = false
        let r = LayoutAwareCorrection.looksLikeMislayoutRussian("12.34",
                                                                isValidRussian: { _ in called = true; return true })
        #expect(!r)
        #expect(!called)
    }
}
