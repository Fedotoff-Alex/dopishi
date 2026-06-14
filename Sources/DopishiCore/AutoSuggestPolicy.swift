import Foundation

public enum AutoSuggestPolicy {
    /// Гейт автоподсказки с причиной отказа (для панели диагностики). Порядок проверок -
    /// от самой блокирующей к мягкой, чтобы причина была самой конкретной.
    public static func evaluate(for ctx: EditingContext, minChars: Int = 3,
                                excluded: Set<String> = []) -> SuggestionGateResult {
        if ctx.isSecure { return .refuse(.secureField) }
        guard ctx.capability == .full else { return .refuse(.noCaretGeometry) }
        guard AppPolicy.isAllowed(bundleId: ctx.appBundleId, excluded: excluded) else { return .refuse(.appExcluded) }
        // Профиль приложения: в терминале и редакторе кода автокомплит молчит по умолчанию
        // (конфликт с shell-автодополнением / IntelliSense). Ручной тап раскладки - мимо.
        guard AppProfile.allowsAutocomplete(AppProfile.category(for: ctx.appBundleId)) else { return .refuse(.appNoAutocomplete) }
        guard ctx.precedingText.count >= minChars else { return .refuse(.belowMinChars) }
        // Каретка в середине текста: ghost рисуется вправо и лёг бы поверх следующего текста.
        // Разрешаем только когда остаток СТРОКИ пуст (после каретки пусто, либо пробелы/табы
        // до переноса строки - дальше текст уже на другой строке, оверлей его не перекрывает).
        guard Self.restOfLineIsEmpty(ctx.followingText) else { return .refuse(.midText) }
        return .allow
    }

    /// Пусто ли до конца строки после каретки (пробелы/табы не считаются текстом).
    public static func restOfLineIsEmpty(_ following: String) -> Bool {
        for ch in following {
            if ch == "\n" || ch == "\r" { return true }
            if ch == " " || ch == "\t" { continue }
            return false
        }
        return true
    }

    /// Стоит ли автоматически просить подсказку для этого контекста.
    public static func shouldSuggest(for ctx: EditingContext, minChars: Int = 3,
                                     excluded: Set<String> = []) -> Bool {
        evaluate(for: ctx, minChars: minChars, excluded: excluded) == .allow
    }
}
