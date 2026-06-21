import Testing
import Foundation
@testable import DopishiApp

// Все тесты резолвят <lang>.lproj ИМЕННО от AppResources.bundle (ресурс-бандл DopishiApp),
// а НЕ от Bundle.module теста (он указывает на бандл тест-таргета, не на DopishiApp).
@Suite struct LocalizationTests {
    private func bundle(_ lang: String) throws -> Bundle {
        let path = try #require(AppResources.bundle.path(forResource: lang, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func ruBundleResolvesRussian() throws {
        let ru = try bundle("ru")
        #expect(NSLocalizedString("settings.system.header", bundle: ru, comment: "") == "Система")
    }

    @Test func enBaseResolvesEnglish() throws {
        let en = try bundle("en")
        #expect(NSLocalizedString("settings.system.header", bundle: en, comment: "") == "System")
    }

    @Test func ruPluralForms() throws {
        let ru = try bundle("ru")
        let fmt = NSLocalizedString("settings.models.count", bundle: ru, comment: "")
        // CLDR-категория plural выбирается по локали, переданной в String(format:locale:).
        // ru.lproj читается под русскую локаль -> явно передаём ru (как в проде: при системном
        // ru Locale.current русский, и one/few/many резолвятся корректно). Без явной локали
        // дефолтная не-русская локаль теста свалит 5 в категорию other ("5 модели").
        let ruLocale = Locale(identifier: "ru_RU")
        #expect(String(format: fmt, locale: ruLocale, 1) == "1 модель")
        #expect(String(format: fmt, locale: ruLocale, 5) == "5 моделей")
    }

    @Test func bundleHasRuLocalization() {
        // Косвенно валидирует, что build-tool plugin отработал и каталог скомпилирован (SC1).
        #expect(AppResources.bundle.localizations.contains("ru"))
    }

    // MD-01: plural-категория должна выбираться по ЯЗЫКУ выбранного бандла, а не по Locale.current.
    // На системе язык=en + регион=ru резолвится ru.lproj, но Locale.current не русский -> «5 модели».
    // Фикс: L привязывает формат-локаль к language ("ru"), полученному из preferredLocalizations,
    // тем же источником, что и под-бандл. Тест моделирует расхождение: бандл ru, Locale.current НЕ ru.
    @Test func ruPluralBoundToBundleLanguageNotLocaleCurrent() throws {
        let ru = try bundle("ru")
        let fmt = NSLocalizedString("settings.models.count", bundle: ru, comment: "")

        // Локаль ИЗ кода языка бандла - ровно то, что делает прод (Locale(identifier: language)).
        // many-форма «5 моделей» доказывает: русский plural выбран по языку бандла.
        let fromBundleLanguage = Locale(identifier: "ru")
        #expect(String(format: fmt, locale: fromBundleLanguage, 1) == "1 модель")
        #expect(String(format: fmt, locale: fromBundleLanguage, 5) == "5 моделей")

        // Контраст: нерусская локаль (как несовпадающий Locale.current) свалила бы 5 в other.
        // Подтверждает, что выбор источника локали - не косметика, а корректность форм.
        let nonRussian = Locale(identifier: "en_US")
        #expect(String(format: fmt, locale: nonRussian, 5) != "5 моделей")
    }
}
