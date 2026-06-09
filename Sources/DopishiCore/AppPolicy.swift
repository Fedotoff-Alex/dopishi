import Foundation

/// Где Dopishi разрешено активничать. Исключения - blacklist по bundleId.
public enum AppPolicy {
    /// Разрешена ли активность для приложения. Неизвестный bundleId (nil) - разрешаем.
    public static func isAllowed(bundleId: String?, excluded: Set<String>) -> Bool {
        guard let bundleId else { return true }
        return !excluded.contains(bundleId)
    }
}
