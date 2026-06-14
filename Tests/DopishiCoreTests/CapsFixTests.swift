import Testing
@testable import DopishiCore

/// Забытый CapsLock: "пРИВЕТ" -> "Привет". Целиком-капс (аббревиатуры) не трогаем.
@Suite struct CapsFixTests {
    @Test func fixesInvertedCaseWord() {
        #expect(CapsFix.fix("пРИВЕТ") == "Привет")
        #expect(CapsFix.fix("hELLO") == "Hello")
        #expect(CapsFix.fix("зАВТРА") == "Завтра")
    }
    @Test func keepsAllCapsWords() {
        // Намеренный капс/аббревиатуры - не наш случай.
        #expect(CapsFix.fix("ПРИВЕТ") == nil)
        #expect(CapsFix.fix("GGUF") == nil)
    }
    @Test func keepsNormalWords() {
        #expect(CapsFix.fix("Привет") == nil)
        #expect(CapsFix.fix("привет") == nil)
        #expect(CapsFix.fix("iPhone") == nil)   // смешанный регистр, не инверсия
    }
    @Test func keepsShortWords() {
        #expect(CapsFix.fix("пР") == nil)
    }
    @Test func ignoresNonLettersInside() {
        #expect(CapsFix.fix("тЕСТ123") == "Тест123")
    }
}
