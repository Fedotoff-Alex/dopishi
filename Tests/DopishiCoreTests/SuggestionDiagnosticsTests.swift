import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct SuggestionDiagnosticsTests {
    private func ctx(text: String = "привет мир", cap: CapabilityTier = .full,
                     secure: Bool = false, app: String? = "com.apple.TextEdit") -> EditingContext {
        EditingContext(precedingText: text, caretScreenRect: cap == .full ? CGRect(x: 0, y: 0, width: 1, height: 14) : nil,
                       appBundleId: app, capability: cap, isSecure: secure)
    }

    @Test func allowWhenEverythingOk() {
        #expect(AutoSuggestPolicy.evaluate(for: ctx()) == .allow)
    }

    @Test func refuseSecure() {
        #expect(AutoSuggestPolicy.evaluate(for: ctx(secure: true)) == .refuse(.secureField))
    }

    @Test func refuseNoCaretGeometry() {
        #expect(AutoSuggestPolicy.evaluate(for: ctx(cap: .textOnly)) == .refuse(.noCaretGeometry))
        #expect(AutoSuggestPolicy.evaluate(for: ctx(cap: .none)) == .refuse(.noCaretGeometry))
    }

    @Test func refuseExcluded() {
        let r = AutoSuggestPolicy.evaluate(for: ctx(app: "com.foo.bar"), excluded: ["com.foo.bar"])
        #expect(r == .refuse(.appExcluded))
    }

    @Test func refuseTerminalAndCodeEditor() {
        #expect(AutoSuggestPolicy.evaluate(for: ctx(app: "com.apple.Terminal")) == .refuse(.appNoAutocomplete))
        #expect(AutoSuggestPolicy.evaluate(for: ctx(app: "com.microsoft.VSCode")) == .refuse(.appNoAutocomplete))
    }

    @Test func refuseBelowMinChars() {
        #expect(AutoSuggestPolicy.evaluate(for: ctx(text: "пр"), minChars: 3) == .refuse(.belowMinChars))
    }

    @Test func shouldSuggestMatchesEvaluate() {
        #expect(AutoSuggestPolicy.shouldSuggest(for: ctx()) == true)
        #expect(AutoSuggestPolicy.shouldSuggest(for: ctx(secure: true)) == false)
    }

    @Test func refusalLabelsAreHumanReadable() {
        // Каждая причина даёт непустой русский ярлык (для панели диагностики).
        for r in [SuggestionRefusal.secureField, .noCaretGeometry, .appExcluded,
                  .appNoAutocomplete, .belowMinChars, .emptyText, .staleContext, .disabled] {
            #expect(!r.label.isEmpty)
        }
    }

    @Test func outcomeLabelsAreHumanReadable() {
        #expect(SuggestionOutcome.correction.label.contains("справлен"))
        #expect(SuggestionOutcome.completion.label.contains("опис") || SuggestionOutcome.completion.label.contains("одсказ"))
        #expect(!SuggestionOutcome.modelEmpty.label.isEmpty)
        #expect(SuggestionOutcome.refused(.secureField).label == SuggestionRefusal.secureField.label)
    }
}
