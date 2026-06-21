import Foundation

// internal-accessor ресурс-бандла DopishiApp - однозначная точка доступа к каталогу.
// Bundle.module здесь = бандл таргета DopishiApp (к нему прилинкован .xcstrings).
// В ОТДЕЛЬНОМ тест-таргете DopishiAppTests Bundle.module указывает на бандл теста,
// а НЕ на DopishiApp, поэтому тест резолвит каталог через AppResources.bundle
// (доступен тесту через @testable import DopishiApp).
enum AppResources {
    static let bundle = Bundle.module
}

enum L {
    // Под-бандл языка системы (ru -> ru.lproj, иначе en.lproj). EN-fallback по D-07.
    // Кэш: резолв один раз за процесс (язык системы не меняется на лету).
    // НЕ String(localized:bundle:.module) - для standalone SwiftPM-продукта .module
    // всегда резолвит en (Pitfall 2); явный под-бандл надёжен и юнит-тестируем.
    // Язык выбранного под-бандла (resolved-локализация). Один резолв за процесс.
    private static let language: String = {
        let available = AppResources.bundle.localizations             // ["en","ru"]
        return Bundle.preferredLocalizations(from: available).first ?? "en" // системный язык, иначе en
    }()

    private static let bundle: Bundle = {
        if let path = AppResources.bundle.path(forResource: language, ofType: "lproj"),
           let b = Bundle(path: path) { return b }
        return AppResources.bundle
    }()

    // Локаль форматирования привязана к языку выбранного бандла, а НЕ к Locale.current (MD-01).
    // Иначе на системе с языком=en, но регионом=ru резолвится ru.lproj, а CLDR-plural-категория
    // берётся по нерусскому Locale.current - и «5 моделей» отрендерилось бы как «5 модели».
    private static let formatLocale = Locale(identifier: language)

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, bundle: bundle, comment: "")
        return args.isEmpty ? fmt : String(format: fmt, locale: formatLocale, arguments: args)
    }
}
