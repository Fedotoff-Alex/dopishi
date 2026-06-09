import Testing
@testable import DopishiCore

@Suite struct SuggestionPreviewTests {
    @Test func stableAfterTrailingSpace() {
        #expect(SuggestionPreview.isStable(" мир "))
    }

    @Test func stableAfterPunctuation() {
        #expect(SuggestionPreview.isStable(" мир."))
    }

    @Test func notStableMidWord() {
        #expect(!SuggestionPreview.isStable(" ми"))
    }

    @Test func notStableEmpty() {
        #expect(!SuggestionPreview.isStable(""))
        #expect(!SuggestionPreview.isStable("   "))
    }
}
