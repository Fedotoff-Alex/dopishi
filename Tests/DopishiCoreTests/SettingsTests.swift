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
}
