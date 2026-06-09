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
}
