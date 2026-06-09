import Testing
@testable import DopishiCore

@Suite struct WordAcceptTests {
    @Test func wordWithTrailingSpace() {
        #expect(WordAccept.firstChunk(of: "привет мир") == "привет ")
    }
    @Test func singleWordNoSpace() {
        #expect(WordAccept.firstChunk(of: "мир") == "мир")
    }
    @Test func leadingSpacePreserved() {
        #expect(WordAccept.firstChunk(of: " мир дом") == " мир ")
    }
    @Test func empty() {
        #expect(WordAccept.firstChunk(of: "") == "")
    }
    @Test func multipleWordsTakeFirst() {
        #expect(WordAccept.firstChunk(of: "a b c") == "a ")
    }
    @Test func punctuationStaysWithWord() {
        #expect(WordAccept.firstChunk(of: "дела, как") == "дела, ")
    }
}
