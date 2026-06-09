import Testing
@testable import DopishiCore

@Suite struct CapabilityTierTests {
    @Test func full_whenTextAndCaret() {
        #expect(Capability.classify(hasText: true, hasCaretRect: true) == .full)
    }

    @Test func textOnly_whenTextNoCaret() {
        #expect(Capability.classify(hasText: true, hasCaretRect: false) == .textOnly)
    }

    @Test func none_whenNoText() {
        #expect(Capability.classify(hasText: false, hasCaretRect: true) == .none)
        #expect(Capability.classify(hasText: false, hasCaretRect: false) == .none)
    }
}
