import Testing
@testable import DopishiCore

@Suite struct ConfidenceGateTests {
    @Test func confidentAboveThreshold() {
        #expect(ConfidenceGate.isConfident(averageLogprob: -1.5, minimum: -3.0))
    }
    @Test func uncertainBelowThreshold() {
        #expect(!ConfidenceGate.isConfident(averageLogprob: -5.0, minimum: -3.0))
    }
    @Test func exactlyAtThreshold() {
        #expect(ConfidenceGate.isConfident(averageLogprob: -3.0, minimum: -3.0))
    }
    @Test func veryConfident() {
        #expect(ConfidenceGate.isConfident(averageLogprob: -0.2, minimum: -3.0))
    }
}
