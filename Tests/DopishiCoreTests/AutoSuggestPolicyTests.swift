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
}
