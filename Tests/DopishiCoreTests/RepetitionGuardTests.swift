import Testing
@testable import DopishiCore

@Suite struct RepetitionGuardTests {
    @Test func collapsesDoubledPhrase() {
        #expect(RepetitionGuard.collapseImmediateRepeat("описал т описал т") == "описал т")
    }
    @Test func collapsesTripled() {
        #expect(RepetitionGuard.collapseImmediateRepeat("да да да") == "да")
        #expect(RepetitionGuard.collapseImmediateRepeat("a b a b a b") == "a b")
    }
    @Test func keepsNonRepeating() {
        #expect(RepetitionGuard.collapseImmediateRepeat("привет мир") == "привет мир")
        #expect(RepetitionGuard.collapseImmediateRepeat("описал текст для") == "описал текст для")
    }
    @Test func suppressesPureEchoOfContext() {
        // подсказка после схлопывания = хвост контекста -> показывать нечего
        #expect(RepetitionGuard.filter(suggestion: "описал т описал т",
                                       context: "Когда можно бы ты описал т") == nil)
        #expect(RepetitionGuard.filter(suggestion: "мир", context: "привет мир") == nil)
    }
    @Test func keepsRealContinuation() {
        #expect(RepetitionGuard.filter(suggestion: "текст для примера",
                                       context: "Когда можно бы ты описал ") == "текст для примера")
        #expect(RepetitionGuard.filter(suggestion: "как дела", context: "привет, ") == "как дела")
    }
    @Test func collapsesThenReturnsWhenNotEcho() {
        // двойной повтор, но не эхо контекста -> вернуть схлопнутую половину
        #expect(RepetitionGuard.filter(suggestion: "привет привет", context: "я сказал ") == "привет")
    }
    @Test func emptyOrWhitespaceSuppressed() {
        #expect(RepetitionGuard.filter(suggestion: "   ", context: "привет") == nil)
    }
    @Test func suppressesCharacterLoop() {
        #expect(RepetitionGuard.looksLikeLoop("0000000"))
        #expect(!RepetitionGuard.looksLikeLoop("привет мир"))
        #expect(RepetitionGuard.filter(suggestion: "2000000000000000", context: "Что будешь ш") == nil)
    }

    // Folded-проверка trailing-дубля (разный регистр и пунктуация)
    @Test func suppressesFoldedEchoUpperCase() {
        // подсказка "МИР" - folded совпадает с хвостом контекста "мир"
        #expect(RepetitionGuard.filter(suggestion: "МИР", context: "привет мир") == nil)
    }
    @Test func suppressesFoldedEchoWithPunctuation() {
        // подсказка "мир!" - folded "мир" совпадает с хвостом контекста
        #expect(RepetitionGuard.filter(suggestion: "мир!", context: "привет мир") == nil)
    }
    @Test func keepsFoldedNonDuplicate() {
        // "мирный" - начинается на "мир" но не является дублём (достаточно отличается)
        let result = RepetitionGuard.filter(suggestion: "мирный договор", context: "привет мир")
        #expect(result != nil)
    }
}
