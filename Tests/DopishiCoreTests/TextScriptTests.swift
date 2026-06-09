import Testing
@testable import DopishiCore

@Suite struct TextScriptTests {
    @Test func cyrillic() { #expect(TextScriptDetector.dominant(of: "привет") == .cyrillic) }
    @Test func latin() { #expect(TextScriptDetector.dominant(of: "hello") == .latin) }
    @Test func neutral() { #expect(TextScriptDetector.dominant(of: "123 !!! ") == .neutral) }
    @Test func mixedLeansToMajority() {
        #expect(TextScriptDetector.dominant(of: "привет hi") == .cyrillic) // 6 cyr > 2 lat
        #expect(TextScriptDetector.dominant(of: "ok привет hello world") == .latin) // 11 lat > 6 cyr
    }
}
