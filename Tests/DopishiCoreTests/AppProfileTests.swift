import Testing
@testable import DopishiCore

@Suite struct AppProfileTests {
    @Test func classifiesTerminals() {
        #expect(AppProfile.category(for: "com.apple.Terminal") == .terminal)
        #expect(AppProfile.category(for: "com.googlecode.iterm2") == .terminal)
        #expect(AppProfile.category(for: "com.mitchellh.ghostty") == .terminal)
    }
    @Test func classifiesCodeEditors() {
        #expect(AppProfile.category(for: "com.microsoft.VSCode") == .codeEditor)
        #expect(AppProfile.category(for: "com.apple.dt.Xcode") == .codeEditor)
        #expect(AppProfile.category(for: "com.todesktop.230313mzl4w4u92") == .codeEditor) // Cursor
        #expect(AppProfile.category(for: "com.jetbrains.intellij") == .codeEditor)        // prefix
    }
    @Test func classifiesBrowsersAndNative() {
        #expect(AppProfile.category(for: "ai.perplexity.comet") == .browser)
        #expect(AppProfile.category(for: "com.apple.Safari") == .browser)
        #expect(AppProfile.category(for: "com.apple.TextEdit") == .native)
    }
    @Test func unknownAndNilDefaultToUnknown() {
        #expect(AppProfile.category(for: "com.some.unknown.app") == .unknown)
        #expect(AppProfile.category(for: nil) == .unknown)
    }
    @Test func suppressesTerminalAndEditorAllowsRest() {
        #expect(AppProfile.allowsAutocomplete(.terminal) == false)
        #expect(AppProfile.allowsAutocomplete(.codeEditor) == false)
        #expect(AppProfile.allowsAutocomplete(.browser) == true)
        #expect(AppProfile.allowsAutocomplete(.native) == true)
        #expect(AppProfile.allowsAutocomplete(.unknown) == true)
    }
}
