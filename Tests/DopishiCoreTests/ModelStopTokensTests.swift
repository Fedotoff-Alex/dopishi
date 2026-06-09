import Testing
@testable import DopishiCore

@Suite struct ModelStopTokensTests {
    @Test func alwaysIncludesNewline() {
        #expect(ModelStopTokens.tokens(for: "anything.gguf").contains("\n"))
    }
    @Test func qwenGetsImEnd() {
        let t = ModelStopTokens.tokens(for: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        #expect(t.contains("<|im_end|>"))
        #expect(t.contains("<|endoftext|>"))
        #expect(!t.contains("<end_of_turn>"))
    }
    @Test func gemma3GetsEndOfTurn() {
        let t = ModelStopTokens.tokens(for: "gemma-3-4b-it-Q4_K_M.gguf")
        #expect(t.contains("<end_of_turn>"))
        #expect(!t.contains("<|im_end|>"))
    }
    @Test func smolLMGetsThinkAndImEnd() {
        let t = ModelStopTokens.tokens(for: "SmolLM3-3B-Q4_K_M.gguf")
        #expect(t.contains("<think>"))
        #expect(t.contains("<|im_end|>"))
    }
    @Test func gemma4E2BStaysNewlineOnly() {
        // Текущая база (gemma-4-E2B) не gemma-3 и не ChatML - только \n.
        let t = ModelStopTokens.tokens(for: "gemma-4-E2B-i1-Q4_K_M.gguf")
        #expect(t == ["\n"])
    }
}
