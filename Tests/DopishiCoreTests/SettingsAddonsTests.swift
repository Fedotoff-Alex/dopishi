import Testing
import Foundation
@testable import DopishiCore

@Suite struct SettingsAddonsTests {
    @Test func defaultsOff() {
        #expect(Settings.default.layoutSwitchEnabled == false)
        #expect(Settings.default.autocorrectEnabled == false)
        #expect(Settings.default.manualLayoutSwitchEnabled == false)
        #expect(Settings.default.excludedBundleIds.isEmpty)
        #expect(Settings.default.disableSystemAutocorrect == false)
        #expect(Settings.default.electronSupport == false)
        #expect(Settings.default.screenContextEnabled == false)
    }
    @Test func roundTrip() throws {
        let s = Settings(layoutSwitchEnabled: true, autocorrectEnabled: true,
                         manualLayoutSwitchEnabled: true, excludedBundleIds: ["com.apple.Terminal"],
                         disableSystemAutocorrect: true, electronSupport: true,
                         screenContextEnabled: true)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
    }
    @Test func oldDataDefaultsOff() throws {
        let old = #"{"enabled":true,"debounceMs":350,"minChars":8,"selectedModelFile":"x.gguf"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: old)
        #expect(s.layoutSwitchEnabled == false)
        #expect(s.autocorrectEnabled == false)
        #expect(s.manualLayoutSwitchEnabled == false)
        #expect(s.excludedBundleIds.isEmpty)
        #expect(s.disableSystemAutocorrect == false)
        #expect(s.electronSupport == false)
        #expect(s.screenContextEnabled == false)
    }
}
