import Foundation

/// Где Dopishi разрешено активничать. Исключения - blacklist по bundleId.
public enum AppPolicy {
    /// Разрешена ли активность для приложения. Неизвестный bundleId (nil) - разрешаем.
    public static func isAllowed(bundleId: String?, excluded: Set<String>) -> Bool {
        guard let bundleId else { return true }
        return !excluded.contains(bundleId)
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
