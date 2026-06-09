import Testing
@testable import DopishiCore

@Suite struct SuggestionJoinTests {
    @Test func stripsLeadingSpaceWhenContextEndsWithSpace() {
        #expect(SuggestionJoin.normalize(" мир", after: "привет ") == "мир")
    }
    @Test func stripsAllLeadingSpaces() {
        #expect(SuggestionJoin.normalize("   мир", after: "привет ") == "мир")
    }
    @Test func keepsLeadingSpaceWhenContextHasNoTrailingSpace() {
        #expect(SuggestionJoin.normalize(" мир", after: "привет") == " мир")
    }
    @Test func noChangeWhenSuggestionHasNoLeadingSpace() {
        #expect(SuggestionJoin.normalize("мир", after: "привет ") == "мир")
    }
    @Test func emptySuggestion() {
        #expect(SuggestionJoin.normalize("", after: "привет ") == "")
    }
    @Test func emptyContextKeepsSuggestion() {
        #expect(SuggestionJoin.normalize(" мир", after: "") == " мир")
    }
    @Test func stripsLeadingSpaceWhenMidWord() {
        // Дописываем незаконченное слово - ведущий пробел был бы ВНУТРИ слова.
        #expect(SuggestionJoin.normalize(" д", after: "велосипе", midWord: true) == "д")
        #expect(SuggestionJoin.normalize("  ить", after: "поступ", midWord: true) == "ить")
    }
    @Test func keepsLeadingSpaceForCompleteWordWithoutMidWord() {
        // Законченное слово без хвостового пробела (midWord=false) - разделитель нужен.
        #expect(SuggestionJoin.normalize(" мир", after: "привет", midWord: false) == " мир")
    }
}
