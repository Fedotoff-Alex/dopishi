import Testing
@testable import DopishiCore

@Suite struct CustomDictionaryTests {
    @Test func normalizeTrimsAndLowercases() {
        #expect(CustomDictionary.normalize("  Anthropic ") == "anthropic")
        #expect(CustomDictionary.normalize("ДОПИШИ") == "допиши")
    }

    @Test func normalizedSetDedupesAndDropsEmpty() {
        let s = CustomDictionary.normalizedSet(["Foo", "foo", "  ", "Bar"])
        #expect(s == ["foo", "bar"])
    }

    @Test func containsIsCaseInsensitive() {
        let s = CustomDictionary.normalizedSet(["Anthropic", "Допиши"])
        #expect(CustomDictionary.contains("anthropic", in: s))
        #expect(CustomDictionary.contains("ДОПИШИ", in: s))
        #expect(!CustomDictionary.contains("привет", in: s))
    }

    @Test func emptyWordNotContained() {
        #expect(!CustomDictionary.contains("", in: ["foo"]))
    }
}
