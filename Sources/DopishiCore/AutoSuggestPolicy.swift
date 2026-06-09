import Foundation

public enum AutoSuggestPolicy {
    /// Стоит ли автоматически просить подсказку для этого контекста.
    public static func shouldSuggest(for ctx: EditingContext, minChars: Int = 3,
                                     excluded: Set<String> = []) -> Bool {
        guard !ctx.isSecure else { return false }
        guard ctx.capability == .full else { return false }
        guard AppPolicy.isAllowed(bundleId: ctx.appBundleId, excluded: excluded) else { return false }
        // Профиль приложения: в терминале и редакторе кода автокомплит молчит по умолчанию
        // (конфликт с shell-автодополнением / IntelliSense). Ручной тап раскладки - мимо.
        guard AppProfile.allowsAutocomplete(AppProfile.category(for: ctx.appBundleId)) else { return false }
        return ctx.precedingText.count >= minChars
    }
}
