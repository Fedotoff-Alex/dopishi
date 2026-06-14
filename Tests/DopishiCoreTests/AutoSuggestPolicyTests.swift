import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct AutoSuggestPolicyTests {
    private func ctx(_ cap: CapabilityTier, text: String, secure: Bool = false) -> EditingContext {
        EditingContext(precedingText: text,
                       caretScreenRect: cap == .full ? CGRect(x: 0, y: 0, width: 1, height: 16) : nil,
                       appBundleId: "com.app", capability: cap, isSecure: secure)
    }

    @Test func suggestsOnFullWithEnoughText() {
        #expect(AutoSuggestPolicy.shouldSuggest(for: ctx(.full, text: "Привет мир")))
    }
    @Test func notOnTooShort() {
        #expect(!AutoSuggestPolicy.shouldSuggest(for: ctx(.full, text: "Пр"), minChars: 3))
    }
    @Test func notOnTextOnly() {
        #expect(!AutoSuggestPolicy.shouldSuggest(for: ctx(.textOnly, text: "Привет мир")))
    }
    @Test func notOnNone() {
        #expect(!AutoSuggestPolicy.shouldSuggest(for: ctx(.none, text: "")))
    }
    @Test func notOnSecure() {
        #expect(!AutoSuggestPolicy.shouldSuggest(for: ctx(.full, text: "пароль123", secure: true)))
    }
    @Test func notWhenExcluded() {
        #expect(!AutoSuggestPolicy.shouldSuggest(for: ctx(.full, text: "Привет мир"),
                                                 excluded: ["com.app"]))
    }
    @Test func suggestsWhenOtherExcluded() {
        #expect(AutoSuggestPolicy.shouldSuggest(for: ctx(.full, text: "Привет мир"),
                                                excluded: ["com.other"]))
    }

    // MARK: - каретка в середине текста (ghost лёг бы поверх)

    @Test func refusesWhenTextFollowsCaret() {
        let ctx = EditingContext(precedingText: "привет, как", caretScreenRect: .init(x: 0, y: 0, width: 1, height: 14),
                                 appBundleId: "com.apple.TextEdit", capability: .full, isSecure: false,
                                 followingText: "дела? Я тут подумал")
        #expect(AutoSuggestPolicy.evaluate(for: ctx) == .refuse(.midText))
    }

    @Test func allowsWhenRestOfLineEmpty() {
        // После каретки перенос строки - на ЭТОЙ строке ghost ничего не перекрывает.
        let ctx = EditingContext(precedingText: "привет, как", caretScreenRect: .init(x: 0, y: 0, width: 1, height: 14),
                                 appBundleId: "com.apple.TextEdit", capability: .full, isSecure: false,
                                 followingText: "\n дальше текст на следующей строке")
        #expect(AutoSuggestPolicy.evaluate(for: ctx) == .allow)
    }

    @Test func allowsAtEndOfText() {
        let ctx = EditingContext(precedingText: "привет, как", caretScreenRect: .init(x: 0, y: 0, width: 1, height: 14),
                                 appBundleId: "com.apple.TextEdit", capability: .full, isSecure: false,
                                 followingText: "")
        #expect(AutoSuggestPolicy.evaluate(for: ctx) == .allow)
    }

    @Test func restOfLineHelper() {
        #expect(AutoSuggestPolicy.restOfLineIsEmpty(""))
        #expect(AutoSuggestPolicy.restOfLineIsEmpty("  \t"))
        #expect(AutoSuggestPolicy.restOfLineIsEmpty(" \nтекст"))
        #expect(!AutoSuggestPolicy.restOfLineIsEmpty("слово"))
        #expect(!AutoSuggestPolicy.restOfLineIsEmpty(" x"))
    }
}
