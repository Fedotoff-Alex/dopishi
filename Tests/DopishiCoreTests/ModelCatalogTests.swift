import Testing
import Foundation
@testable import DopishiCore

@Suite struct ModelCatalogTests {
    @Test func hasEightPresets() {
        #expect(ModelCatalog.presets.count == 8)
    }
    // D-11: каждый tier - стабильный id (App локализует через L.tr), не пустой, с префиксом model.tier.
    @Test func everyPresetTierIsStableId() {
        for p in ModelCatalog.presets {
            #expect(!p.tier.isEmpty)
            #expect(p.tier.hasPrefix("model.tier."))
        }
    }
    // MODEL-01: T-lite от Т-Банка (t-tech), официальный GGUF, Apache 2.0.
    @Test func tlitePresetIsApacheLicensed() {
        let t = ModelCatalog.preset(id: "T-lite-it-2.1-Q4_K_M.gguf")
        #expect(t != nil)
        #expect(t?.license == .apache2)
        #expect(t?.downloadURL.absoluteString == "https://huggingface.co/t-tech/T-lite-it-2.1-GGUF/resolve/main/T-lite-it-2.1-Q4_K_M.gguf")
    }
    // MODEL-02: YandexGPT в каталоге с ЯВНОЙ кастомной лицензией (не MIT/Apache) и URL.
    @Test func yandexPresetHasCustomLicenseAndURL() {
        let y = ModelCatalog.preset(id: "YandexGPT-5-Lite-8B-instruct-Q4_K_M.gguf")
        #expect(y != nil)
        guard let y else { return }
        #expect(y.downloadURL.absoluteString == "https://huggingface.co/yandex/YandexGPT-5-Lite-8B-instruct-GGUF/resolve/main/YandexGPT-5-Lite-8B-instruct-Q4_K_M.gguf")
        #expect(y.approxSizeGB == 4.9)
        if case let .custom(name, url) = y.license {
            #expect(name.contains("Yandex"))
            #expect(url.contains("huggingface.co/yandex/YandexGPT-5-Lite-8B-instruct-GGUF"))
        } else {
            Issue.record("YandexGPT обязан иметь license == .custom (MODEL-02), получено: \(y.license)")
        }
    }
    @Test func qwenPresetsAreApache2() {
        #expect(ModelCatalog.preset(id: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")?.license == .apache2)
        #expect(ModelCatalog.preset(id: "Qwen3.5-4B-Q4_K_M.gguf")?.license == .apache2)
    }
    @Test func gemmaPresetsAreCustomLicensed() {
        // Gemma - НЕ Apache: своя Gemma Terms of Use.
        if case .custom = ModelCatalog.preset(id: "gemma-3-4b-it-Q4_K_M.gguf")!.license {} else {
            Issue.record("Gemma license должна быть .custom")
        }
    }
    @Test func qwen3InstructPresetURL() {
        let p = ModelCatalog.preset(id: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!
        // D-11: tier - стабильный id назначения (App локализует через L.tr), не русский текст.
        #expect(p.tier == "model.tier.bestRu")
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
