import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct GhostFontMetricsTests {
    // С метриками шрифта: ratio = 12/(10-(-3)) = 12/13, result = 20 * (12/13) ~= 18.46
    @Test func withFieldMetrics() {
        let result = GhostFontMetrics.pointSize(
            caretHeight: 20,
            fieldPointSize: 12,
            fieldAscender: 10,
            fieldDescender: -3
        )
        #expect(abs(result - 18.46) < 0.1)
    }

    // Без метрик: fallbackRatio = 0.72, result = 20 * 0.72 = 14.4
    @Test func withoutFieldMetrics() {
        let result = GhostFontMetrics.pointSize(caretHeight: 20)
        #expect(abs(result - 14.4) < 0.01)
    }

    // Clamp снизу: 5 * 0.72 = 3.6, но minimum = 9
    @Test func clampMinimum() {
        let result = GhostFontMetrics.pointSize(caretHeight: 5, fallbackRatio: 0.72)
        #expect(result == 9)
    }

    // Clamp сверху: 100 * 0.72 = 72, но maximum = 48
    @Test func clampMaximum() {
        let result = GhostFontMetrics.pointSize(caretHeight: 100)
        #expect(result == 48)
    }
}
