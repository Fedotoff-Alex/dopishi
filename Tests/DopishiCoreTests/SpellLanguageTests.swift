import Testing
@testable import DopishiCore

@Suite struct SpellLanguageTests {
    @Test func cyrillicIsRu() { #expect(SpellLanguage.code(for: "привет") == "ru") }
    @Test func latinIsEn() { #expect(SpellLanguage.code(for: "hello") == "en") }
    @Test func digitsAreNil() { #expect(SpellLanguage.code(for: "12345") == nil) }
    @Test func emptyIsNil() { #expect(SpellLanguage.code(for: "") == nil) }
    @Test func punctuationIsNil() { #expect(SpellLanguage.code(for: "!!!") == nil) }
}
