import Testing
@testable import DopishiCore

@Suite struct SuggestionGateTests {
    @Test func emptyIsNotPresentable() {
        #expect(!SuggestionGate.isPresentable(""))
    }
    @Test func whitespaceAndNewlineNotPresentable() {
        #expect(!SuggestionGate.isPresentable("   "))
        #expect(!SuggestionGate.isPresentable("\n"))
        #expect(!SuggestionGate.isPresentable("  \n \t "))
    }
    @Test func realTextIsPresentable() {
        #expect(SuggestionGate.isPresentable("привет"))
        #expect(SuggestionGate.isPresentable(" a "))
    }
}
