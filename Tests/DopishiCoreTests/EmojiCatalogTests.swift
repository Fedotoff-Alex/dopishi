import Testing
@testable import DopishiCore

@Suite struct EmojiCatalogTests {
    @Test func exactMatch() {
        #expect(EmojiCatalog.match(name: "fire") == "🔥")
        #expect(EmojiCatalog.match(name: "heart") == "❤️")
        #expect(EmojiCatalog.match(name: "rocket") == "🚀")
    }

    @Test func caseInsensitive() {
        #expect(EmojiCatalog.match(name: "FIRE") == "🔥")
    }

    @Test func prefixMatchPrefersShortestThenLexical() {
        // префикс "sm": smile(5), smirk(5), smiley(6) -> кратчайшие smile/smirk, smile < smirk
        #expect(EmojiCatalog.match(name: "sm") == "😄")
    }

    @Test func tooShortReturnsNil() {
        #expect(EmojiCatalog.match(name: "f") == nil)
        #expect(EmojiCatalog.match(name: "") == nil)
    }

    @Test func unknownReturnsNil() {
        #expect(EmojiCatalog.match(name: "qwxyz") == nil)
    }
}
