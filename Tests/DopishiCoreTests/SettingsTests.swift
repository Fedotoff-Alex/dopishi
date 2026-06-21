import Testing
import Foundation
@testable import DopishiCore

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = Settings.default
        #expect(s.enabled == true)
        #expect(s.debounceMs == 150)
        #expect(s.minChars == 8)
    }
    @Test func clampsBounds() {
        let lo = Settings(enabled: true, debounceMs: 10, minChars: 0).clamped()
        #expect(lo.debounceMs == 60)
        #expect(lo.minChars == 1)
        let hi = Settings(enabled: true, debounceMs: 9999, minChars: 999).clamped()
        #expect(hi.debounceMs == 1500)
        #expect(hi.minChars == 20)
    }
    @Test func codableRoundTrip() throws {
        let s = Settings(enabled: false, debounceMs: 400, minChars: 5)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back == s)
    }
    // MODEL-03 D-04: дефолт manuallySelected == false (рекомендация активна до ручного выбора).
    @Test func manuallySelectedDefaultsFalse() {
        #expect(Settings.default.manuallySelected == false)
    }
    // SC3 (часть): старый persisted JSON без ключа manuallySelected -> false (backward-compat).
    @Test func decodesOldDataWithoutManuallySelected() throws {
        let old = #"{"selectedModelFile":"Qwen3.5-4B-Q4_K_M.gguf"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: old)
        #expect(s.manuallySelected == false)
    }
    // manuallySelected=true переживает encode/decode round-trip.
    @Test func manuallySelectedRoundTrip() throws {
        let s = Settings(manuallySelected: true)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back.manuallySelected == true)
    }
}
