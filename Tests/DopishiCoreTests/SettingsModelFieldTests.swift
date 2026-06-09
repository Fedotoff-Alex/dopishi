import Testing
import Foundation
@testable import DopishiCore

@Suite struct SettingsModelFieldTests {
    @Test func defaultModelFile() {
        #expect(Settings.default.selectedModelFile == "Qwen3.5-4B-Q4_K_M.gguf")
    }
    @Test func roundTripWithModel() throws {
        let s = Settings(enabled: true, debounceMs: 350, minChars: 3, selectedModelFile: "Qwen3.5-9B-Q4_K_M.gguf")
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
    }
    @Test func decodesOldDataWithoutModelField() throws {
        // старые сохранённые настройки без selectedModelFile -> дефолт
        let old = #"{"enabled":true,"debounceMs":400,"minChars":4}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: old)
        #expect(s.debounceMs == 400)
        #expect(s.selectedModelFile == "Qwen3.5-4B-Q4_K_M.gguf")
    }
}
