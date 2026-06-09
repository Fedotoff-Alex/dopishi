import Testing
@testable import DopishiCore

@Suite struct LanguageGuardTests {
    @Test func suppressLatinOnCyrillicContext() {
        #expect(!LanguageGuard.allows(suggestion: "hello world", givenContext: "привет, как "))
    }
    @Test func allowCyrillicOnCyrillicContext() {
        #expect(LanguageGuard.allows(suggestion: "дела", givenContext: "привет, как "))
    }
    @Test func suppressUkrainianDriftOnRussianContext() {
        #expect(!LanguageGuard.allows(suggestion: "це дуже важливо", givenContext: "привет, как "))
        #expect(!LanguageGuard.allows(suggestion: "і продолжить дальше", givenContext: "надо "))
    }
    @Test func allowUkrainianWhenContextAlreadyUkrainian() {
        #expect(LanguageGuard.allows(suggestion: "це дуже важливо", givenContext: "привіт, як "))
    }
    @Test func doNotInterfereOnLatinContext() {
        #expect(LanguageGuard.allows(suggestion: "world", givenContext: "hello "))
    }
    @Test func allowNeutralSuggestion() {
        #expect(LanguageGuard.allows(suggestion: ", ", givenContext: "привет"))
        #expect(LanguageGuard.allows(suggestion: "2024", givenContext: "год "))
    }
}
