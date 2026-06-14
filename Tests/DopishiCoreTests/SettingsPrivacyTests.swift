import Testing
import Foundation
@testable import DopishiCore

/// Phase 4 (Onboarding + Privacy): новые поля настроек.
@Suite struct SettingsPrivacyTests {
    @Test func defaults() {
        let s = Settings.default
        #expect(s.onboardingCompleted == false)
        #expect(s.memoryTTLDays == 7)
        #expect(s.memoryExcludedBundleIds.isEmpty)
        // Решение вехи: события подсказок включены по умолчанию начиная с Phase 4
        // (Privacy Center даёт контроль). До этого default-OFF.
        #expect(s.suggestionTelemetryEnabled == true)
    }

    @Test func clampsTTL() {
        var s = Settings.default
        s.memoryTTLDays = 0
        #expect(s.clamped().memoryTTLDays == 1)
        s.memoryTTLDays = 999
        #expect(s.clamped().memoryTTLDays == 90)
        s.memoryTTLDays = 7
        #expect(s.clamped().memoryTTLDays == 7)
    }

    /// Старый persisted JSON без новых ключей декодируется в дефолты (миграция).
    @Test func decodeLegacyJSONFillsDefaults() throws {
        let legacy = #"{"enabled":true,"debounceMs":150,"minChars":8,"selectedModelFile":"x.gguf"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(legacy.utf8))
        #expect(s.onboardingCompleted == false)
        #expect(s.memoryTTLDays == 7)
        #expect(s.memoryExcludedBundleIds.isEmpty)
        #expect(s.suggestionTelemetryEnabled == true)
    }

    @Test func codableRoundTrip() throws {
        var s = Settings.default
        s.onboardingCompleted = true
        s.memoryTTLDays = 30
        s.memoryExcludedBundleIds = ["com.example.app"]
        s.suggestionTelemetryEnabled = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back == s)
    }
}
