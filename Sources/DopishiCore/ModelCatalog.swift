import Foundation

/// Лицензия модели. Явное поле (MODEL-02): проприетарные модели (YandexGPT, Gemma)
/// нельзя молча выдавать за MIT/Apache - у них свои условия использования.
public enum ModelLicense: Equatable, Sendable {
    case apache2
    case mit
    /// Кастомная лицензия: имя + URL полного текста.
    case custom(name: String, url: String)
}

public struct ModelPreset: Equatable, Sendable, Identifiable {
    public let id: String          // = fileName (уникально, локальное имя)
    public let displayName: String // короткое имя модели (напр. "Qwen3.5 4B")
    public let tier: String        // стабильный id назначения (напр. "model.tier.balanced"); локализуется в App (D-11)
    public let repo: String        // HF репозиторий
    public let fileName: String    // локальное имя gguf (путь на диске)
    public let remoteFileName: String  // имя файла в репозитории HF (иногда отличается от локального)
    public let approxSizeGB: Double
    public let license: ModelLicense

    public init(displayName: String, tier: String, repo: String, fileName: String,
                remoteFileName: String? = nil, approxSizeGB: Double,
                license: ModelLicense = .apache2) {
        self.id = fileName
        self.displayName = displayName
        self.tier = tier
        self.repo = repo
        self.fileName = fileName
        self.remoteFileName = remoteFileName ?? fileName
        self.approxSizeGB = approxSizeGB
        self.license = license
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(remoteFileName)")!
    }
}

public enum ModelCatalog {
    public static let presets: [ModelPreset] = [
        ModelPreset(displayName: "Qwen3.5 2B", tier: "model.tier.fast",
                    repo: "lmstudio-community/Qwen3.5-2B-GGUF",
                    fileName: "Qwen3.5-2B-Q4_K_M.gguf", approxSizeGB: 1.4),
        ModelPreset(displayName: "Qwen3.5 4B", tier: "model.tier.balanced",
                    repo: "lmstudio-community/Qwen3.5-4B-GGUF",
                    fileName: "Qwen3.5-4B-Q4_K_M.gguf", approxSizeGB: 2.5),
        ModelPreset(displayName: "Qwen3.5 9B", tier: "model.tier.quality",
                    repo: "lmstudio-community/Qwen3.5-9B-GGUF",
                    fileName: "Qwen3.5-9B-Q4_K_M.gguf", approxSizeGB: 5.5),
        ModelPreset(displayName: "Gemma 4 E2B", tier: "model.tier.compact",
                    repo: "mradermacher/gemma-4-E2B-i1-GGUF",
                    fileName: "gemma-4-E2B-i1-Q4_K_M.gguf",
                    remoteFileName: "gemma-4-E2B.i1-Q4_K_M.gguf", approxSizeGB: 3.5,
                    license: .custom(name: "Gemma Terms of Use",
                                     url: "https://ai.google.dev/gemma/terms")),
        // Лучшее RU в классе 4B по прямому бенчу (10/10 принято против 7/10 у Gemma-4-E2B,
        // выше уверенность, вытягивает mid-word/newline). Нативно non-thinking, Apache-2.0.
        ModelPreset(displayName: "Qwen3-4B Instruct 2507", tier: "model.tier.bestRu",
                    repo: "bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF",
                    fileName: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
                    remoteFileName: "Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf", approxSizeGB: 2.5),
        // Близкий №2 по бенчу (тоже 10/10, сильное RU), но prompt-sensitive. Брать только
        // официальный ggml-org GGUF (корректные control-токены).
        ModelPreset(displayName: "Gemma 3 4B IT", tier: "model.tier.strongRu",
                    repo: "ggml-org/gemma-3-4b-it-GGUF",
                    fileName: "gemma-3-4b-it-Q4_K_M.gguf", approxSizeGB: 2.5,
                    license: .custom(name: "Gemma Terms of Use",
                                     url: "https://ai.google.dev/gemma/terms")),
        // Официальный GGUF Т-Банка (Qwen3-8B база, Apache 2.0) - «лайт»-линейка t-tech (MODEL-01).
        ModelPreset(displayName: "T-lite 2.1 (Т-Банк)", tier: "model.tier.qualityRuApache",
                    repo: "t-tech/T-lite-it-2.1-GGUF",
                    fileName: "T-lite-it-2.1-Q4_K_M.gguf", approxSizeGB: 5.0),
        // Официальный GGUF Яндекса (llama-арх). Лицензия - СВОЯ (Yandex), не MIT/Apache:
        // локальное некоммерческое/коммерческое использование - см. текст по URL (MODEL-02).
        // Движок работает в .plain-режиме (литеральная голова промпта) - chat-template не нужен.
        ModelPreset(displayName: "YandexGPT 5 Lite 8B", tier: "model.tier.qualityRu",
                    repo: "yandex/YandexGPT-5-Lite-8B-instruct-GGUF",
                    fileName: "YandexGPT-5-Lite-8B-instruct-Q4_K_M.gguf", approxSizeGB: 4.9,
                    license: .custom(name: "Yandex License",
                                     url: "https://huggingface.co/yandex/YandexGPT-5-Lite-8B-instruct-GGUF/blob/main/LICENSE")),
    ]

    public static let defaultFileName = "Qwen3.5-4B-Q4_K_M.gguf"

    public static func preset(id: String) -> ModelPreset? {
        presets.first { $0.id == id }
    }

    /// Грубая эвристика: модель + накладные (~2.5x размера) помещаются в ОЗУ.
    public static func fitsComfortably(_ p: ModelPreset, ramGB: Double) -> Bool {
        p.approxSizeGB * 2.5 <= ramGB
    }

    /// Рекомендованная модель под язык системы с учётом RAM (MODEL-03, D-01/D-02).
    /// Язык приходит идентификатором СТРОКОЙ (App читает Locale.preferredLanguages.first) -
    /// Core систему не читает, функция чистая и юнит-тестируема без системной локали.
    /// Идёт по приоритет-списку tier-id языка, возвращает ПЕРВЫЙ влезающий (fitsComfortably).
    /// Если ничего из языка не влезло - лёгкий мультиязычный fallback (tier fast). Никогда не nil.
    public static func recommended(forLocale locale: String, ramGB: Double) -> ModelPreset {
        let isRu = Locale(identifier: locale).language.languageCode?.identifier == "ru"
        let tiers = isRu
            ? ["model.tier.bestRu", "model.tier.qualityRuApache", "model.tier.qualityRu", "model.tier.strongRu"]
            : ["model.tier.quality", "model.tier.balanced", "model.tier.fast"]
        let candidates = tiers.compactMap { tier in presets.first { $0.tier == tier } }
        if let fit = candidates.first(where: { fitsComfortably($0, ramGB: ramGB) }) { return fit }
        // Fallback (D-02): ни одна модель языка не влезла -> лёгкая мультиязычная.
        // presets.first гарантированно non-nil (fast всегда в каталоге); крайний guard - первый пресет.
        return presets.first { $0.tier == "model.tier.fast" } ?? presets[0]
    }
}
