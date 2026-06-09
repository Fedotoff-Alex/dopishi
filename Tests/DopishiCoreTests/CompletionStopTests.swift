import Testing
@testable import DopishiCore

@Suite struct CompletionStopTests {
    @Test func stopsOnNewline() {
        let r = CompletionStop.evaluate(" пойти гулять\nи ещё", maxWords: 20)
        #expect(r.shouldStop)
        #expect(r.trimmed == " пойти гулять")
    }
    @Test func stopsOnSentenceEnd() {
        let r = CompletionStop.evaluate(" пойти гулять. И ещё", maxWords: 20)
        #expect(r.shouldStop)
        #expect(r.trimmed == " пойти гулять.")
    }
    @Test func stopsOnWordLimit() {
        let r = CompletionStop.evaluate(" один два три четыре пять", maxWords: 3)
        #expect(r.shouldStop)
        #expect(r.trimmed == " один два три")
    }
    @Test func keepsGoingWhenShort() {
        let r = CompletionStop.evaluate(" пойти", maxWords: 20)
        #expect(!r.shouldStop)
        #expect(r.trimmed == " пойти")
    }
}
