import Foundation

/// Где Dopishi разрешено активничать. Исключения - blacklist по bundleId.
public enum AppPolicy {
    /// Встроенные исключения: системные поля, где Допиши не действует вообще. Spotlight -
    /// мгновенный поиск: инъекция (backspace+вставка) гонится с перерисовкой поля и оставляет
    /// артефакты, а контекста для свитча раскладки нет (поле на одно слово). Это техническое
    /// ограничение, не выбор пользователя - в UI-списке исключений НЕ показывается.
    public static let builtInExcluded: Set<String> = [
        "com.apple.Spotlight",   // системный поиск Spotlight
    ]

    /// Разрешена ли активность для приложения. Неизвестный bundleId (nil) - разрешаем.
    public static func isAllowed(bundleId: String?, excluded: Set<String>) -> Bool {
        guard let bundleId else { return true }
        return !excluded.contains(bundleId) && !builtInExcluded.contains(bundleId)
    }

    /// Можно ли писать текст поля в персистентную память: non-secure поле И приложение
    /// не исключено И не помечено «не учиться в этом приложении» (Privacy Center, UX-02:
    /// подсказки в нём работают, но память из него не пишется). Зеркалит контракт
    /// MemoryProvider.record («только allowed + non-secure текст») - вызывающие гейтят
    /// запись этим предикатом (defense-in-depth).
    public static func allowsMemoryWrite(isSecure: Bool, bundleId: String?, excluded: Set<String>,
                                         learningExcluded: Set<String> = []) -> Bool {
        guard !isSecure, isAllowed(bundleId: bundleId, excluded: excluded) else { return false }
        guard let bundleId else { return true }
        return !learningExcluded.contains(bundleId)
    }
}
