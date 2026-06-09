import Testing
@testable import DopishiCore

@Suite struct RejectionTallyTests {
    @Test func startsEmpty() {
        let t = RejectionTally()
        #expect(t.shown == 0)
        #expect(t.totalRejected == 0)
    }

    @Test func recordsShownWithoutMutatingOriginal() {
        let t0 = RejectionTally()
        let t1 = t0.recordingShown(app: "com.apple.TextEdit")
        #expect(t0.shown == 0)   // исходный не изменился
        #expect(t1.shown == 1)
    }

    @Test func recordsReasonGloballyAndPerApp() {
        let t = RejectionTally()
            .recording(reason: .lowConfidence, app: "com.apple.Safari")
            .recording(reason: .lowConfidence, app: "com.apple.Safari")
            .recording(reason: .languageMismatch, app: "com.apple.Mail")
        #expect(t.totalRejected == 3)
        #expect(t.byReason[.lowConfidence] == 2)
        #expect(t.byReason[.languageMismatch] == 1)
        #expect(t.byApp["com.apple.Safari"]?[.lowConfidence] == 2)
        #expect(t.byApp["com.apple.Mail"]?[.languageMismatch] == 1)
    }

    @Test func nilAppBucketsUnderDash() {
        let t = RejectionTally().recording(reason: .repetition, app: nil)
        #expect(t.byApp["-"]?[.repetition] == 1)
    }

    @Test func summaryListsShownAndReasons() {
        let t = RejectionTally()
            .recordingShown(app: "a")
            .recording(reason: .empty, app: "a")
        #expect(t.summary().contains("shown=1"))
        #expect(t.summary().contains("rejected=1"))
        #expect(t.summary().contains("empty=1"))
    }
}
