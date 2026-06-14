import Testing
import Foundation
@testable import DopishiCore

@Suite struct SuggestionEventTests {
    @Test func outcomeRawValues() {
        #expect(SuggestionEventOutcome.shown.rawValue == "shown")
        #expect(SuggestionEventOutcome.typedThrough.rawValue == "typedThrough")
        #expect(SuggestionEventOutcome(rawValue: "accepted") == .accepted)
        #expect(SuggestionEventOutcome.allCases.count == 6)
    }

    @Test func eventStoresAllFields() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let e = SuggestionEvent(threadKey: "com.app:7", appBundleId: "com.app",
                                outcome: "shown", refusalReason: nil,
                                latencyFirstMs: 120, latencyTotalMs: 300,
                                modelFile: "m.gguf", promptMode: "chat",
                                kind: "completion", createdAt: now)
        #expect(e.threadKey == "com.app:7")
        #expect(e.latencyFirstMs == 120)
        #expect(e.latencyTotalMs == 300)
        #expect(e.kind == "completion")
        #expect(e == e)
    }

    @Test func kindDefaultsToNil() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let e = SuggestionEvent(threadKey: "com.app:7", appBundleId: "com.app",
                                outcome: "refused", refusalReason: "emptyText",
                                latencyFirstMs: nil, latencyTotalMs: nil,
                                modelFile: nil, promptMode: nil, createdAt: now)
        #expect(e.kind == nil)
    }
}
