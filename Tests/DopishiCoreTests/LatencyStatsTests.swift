import Testing
@testable import DopishiCore

@Suite struct LatencyStatsTests {
    @Test func emptyReturnsZero() {
        let r = LatencyStats.percentiles([])
        #expect(r.p50 == 0)
        #expect(r.p95 == 0)
    }
    @Test func singleValue() {
        let r = LatencyStats.percentiles([150])
        #expect(r.p50 == 150)
        #expect(r.p95 == 150)
    }
    @Test func medianOfOddCount() {
        let r = LatencyStats.percentiles([10, 20, 30, 40, 50])
        #expect(r.p50 == 30)
    }
    @Test func unsortedInputSortedInternally() {
        let r = LatencyStats.percentiles([50, 10, 30, 20, 40])
        #expect(r.p50 == 30)
    }
    @Test func p50NeverExceedsP95() {
        let r = LatencyStats.percentiles([5, 1, 9, 3, 7, 100, 2, 8])
        #expect(r.p50 <= r.p95)
    }
}
