import Testing
import Foundation
@testable import DopishiCore

@Suite struct ModelCatalogTests {
    @Test func hasSixPresets() {
        #expect(ModelCatalog.presets.count == 6)
    }
    @Test func qwen3InstructPresetURL() {
        let p = ModelCatalog.preset(id: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!
        #expect(p.tier == "лучшее RU")
        // remoteFileName с префиксом Qwen_, локальное имя без него (проверенный bartowski URL).
        #expect(p.downloadURL.absoluteString == "https://huggingface.co/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
    }
    @Test func lookupById() {
        #expect(ModelCatalog.preset(id: "Qwen3.5-4B-Q4_K_M.gguf")?.approxSizeGB == 2.5)
        #expect(ModelCatalog.preset(id: "нет") == nil)
    }
    @Test func downloadURL() {
        let p = ModelCatalog.preset(id: "Qwen3.5-2B-Q4_K_M.gguf")!
        #expect(p.downloadURL.absoluteString == "https://huggingface.co/lmstudio-community/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")
    }
    @Test func gemmaUsesRemoteFileNameInURL() {
        let g = ModelCatalog.preset(id: "gemma-4-E2B-i1-Q4_K_M.gguf")!
        // локальное имя с дефисом, имя в репозитории - с точкой
        #expect(g.downloadURL.absoluteString == "https://huggingface.co/mradermacher/gemma-4-E2B-i1-GGUF/resolve/main/gemma-4-E2B.i1-Q4_K_M.gguf")
    }
    @Test func fitsByRam() {
        let small = ModelCatalog.preset(id: "Qwen3.5-2B-Q4_K_M.gguf")!
        let big = ModelCatalog.preset(id: "Qwen3.5-9B-Q4_K_M.gguf")!
        #expect(ModelCatalog.fitsComfortably(small, ramGB: 8))
        #expect(!ModelCatalog.fitsComfortably(big, ramGB: 8))   // 5.5*2.5=13.75 > 8
        #expect(ModelCatalog.fitsComfortably(big, ramGB: 16))   // 13.75 <= 16
    }
}
