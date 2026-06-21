import Testing
import Foundation
@testable import DopishiCore

/// Покрытие чистой функции ModelCatalog.recommended(forLocale:ramGB:) - MODEL-03, SC1/SC2/SC4.
/// Вход ЯВНЫЙ (Locale-строка + ramGB число), системная локаль не читается - функция юнит-тестируема.
/// Адресация по preset(id:)?.fileName / .tier (как ModelCatalogTests), tier-id стабильны (D-01).
@Suite struct ModelRecommendTests {
    // SC1: ru при достаточной RAM -> Qwen3-4B Instruct 2507 (tier bestRu, 2.5*2.5=6.25 <= 8).
    @Test func ruHighRamPicksBestRu() {
        let r = ModelCatalog.recommended(forLocale: "ru", ramGB: 8)
        #expect(r.fileName == "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
    }
    // SC1: ru-детекция по language code (полный идентификатор ru_RU), не точное совпадение строки.
    @Test func ruFullIdentifierPicksBestRu() {
        let r = ModelCatalog.recommended(forLocale: "ru_RU", ramGB: 8)
        #expect(r.tier == "model.tier.bestRu")
    }
    // SC1: en при высокой RAM -> Qwen3.5 9B (tier quality, 5.5*2.5=13.75 <= 16).
    @Test func enHighRamPicksQuality() {
        let r = ModelCatalog.recommended(forLocale: "en", ramGB: 16)
        #expect(r.fileName == "Qwen3.5-9B-Q4_K_M.gguf")
    }
    // SC2: прочий (не-ru) язык обрабатывается как en-линейка -> quality.
    @Test func otherLanguageTreatedAsEn() {
        let r = ModelCatalog.recommended(forLocale: "de", ramGB: 16)
        #expect(r.tier == "model.tier.quality")
    }
    // SC4: en средняя RAM - деградация (9B 13.75>8 не влезает -> balanced 2.5*2.5=6.25<=8).
    @Test func enMidRamDegradesToBalanced() {
        let r = ModelCatalog.recommended(forLocale: "en", ramGB: 8)
        #expect(r.fileName == "Qwen3.5-4B-Q4_K_M.gguf")
    }
    // SC4: ru очень мало RAM - вся ru-линейка не влезает -> мультиязычный fallback (tier fast).
    // bestRu 6.25>4, T-lite 12.5>4, YandexGPT 12.25>4, Gemma3 6.25>4 -> fallback fast 1.4*2.5=3.5<=4.
    @Test func ruTinyRamFallsBackToFast() {
        let r = ModelCatalog.recommended(forLocale: "ru", ramGB: 4)
        #expect(r.tier == "model.tier.fast")
    }
    // SC4: non-nil гарантия на крайне малой RAM - ничего не влезает, всё равно fast (не nil).
    @Test func extremelyLowRamStillReturnsFast() {
        let r = ModelCatalog.recommended(forLocale: "en", ramGB: 1)
        #expect(r.tier == "model.tier.fast")
    }
}
