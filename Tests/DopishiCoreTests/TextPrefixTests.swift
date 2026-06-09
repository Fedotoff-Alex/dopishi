import Testing
@testable import DopishiCore

@Suite struct TextPrefixTests {
    @Test func asciiPrefixByUTF16Offset() {
        #expect(TextPrefix.byUTF16Offset("hello", offset: 2) == "he")
        #expect(TextPrefix.byUTF16Offset("hello", offset: 5) == "hello")
    }

    @Test func outOfRangeKeepsFullText() {
        #expect(TextPrefix.byUTF16Offset("hello", offset: -1) == "hello")
        #expect(TextPrefix.byUTF16Offset("hello", offset: 99) == "hello")
    }

    @Test func emojiUsesUTF16Offset() {
        let text = "a🙂b" // UTF-16 offsets: a=1, emoji=2, b=1
        #expect(text.count == 3)
        #expect(text.utf16.count == 4)
        #expect(TextPrefix.byUTF16Offset(text, offset: 3) == "a🙂")
    }

    @Test func invalidSurrogateBoundaryFallsBackToPreviousValidPrefix() {
        #expect(TextPrefix.byUTF16Offset("a🙂b", offset: 2) == "a")
    }

    @Test func combiningMarkOffsetKeepsComposedPrefix() {
        let text = "e\u{301}x"
        #expect(text.utf16.count == 3)
        #expect(TextPrefix.byUTF16Offset(text, offset: 2) == "e\u{301}")
    }
}
