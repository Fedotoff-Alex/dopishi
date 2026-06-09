import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct ContextFreshnessTests {
    private func ctx(_ preceding: String, typed: String) -> EditingContext {
        EditingContext(precedingText: preceding, caretScreenRect: .zero, appBundleId: "x",
                       capability: .full, isSecure: false, typedSinceFocus: typed)
    }

    @Test func emptyBufferTrustsAX() {
        #expect(ContextFreshness.isFresh(ctx("давай про", typed: "")))
    }

    @Test func prefixEndingWithTypedIsFresh() {
        // Поле было пустым, набрано "давай про", AX догнал.
        #expect(ContextFreshness.isFresh(ctx("давай про", typed: "давай про")))
    }

    @Test func staleAXMissingLatestCharsDetected() {
        // Баг из Claude: AX отдаёт "давай ", а напечатано уже "давай про" -> устарел.
        #expect(!ContextFreshness.isFresh(ctx("давай ", typed: "давай про")))
        #expect(!ContextFreshness.isFresh(ctx("давай п", typed: "давай про")))
    }

    @Test func preExistingTextWithFreshTail() {
        // В поле было "Привет, ", дописали "как дела" - AX свежий оканчивается на набранное.
        #expect(ContextFreshness.isFresh(ctx("Привет, как дела", typed: "как дела")))
        // AX отстал на хвост -> устарел.
        #expect(!ContextFreshness.isFresh(ctx("Привет, как де", typed: "как дела")))
    }
}
