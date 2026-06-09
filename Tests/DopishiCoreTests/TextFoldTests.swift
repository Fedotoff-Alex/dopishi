import Testing
@testable import DopishiCore

@Suite struct TextFoldTests {
    @Test func foldsCyrillicWithPunctuation() {
        #expect(TextFold.folded("Привет, Мир!") == "приветмир")
    }
    @Test func foldsAsciiWithSpecials() {
        #expect(TextFold.folded("a-b_c") == "abc")
    }
    @Test func emptyStaysEmpty() {
        #expect(TextFold.folded("") == "")
    }
    @Test func lowercasesLatin() {
        #expect(TextFold.folded("Hello World") == "helloworld")
    }
    @Test func keepsDigits() {
        #expect(TextFold.folded("abc123!@#") == "abc123")
    }
}
