import CoreGraphics
import AppKit

/// Гейт разрешения Screen Recording (TCC). Отдельно от Accessibility/Input Monitoring.
/// CGPreflight - проверка без диалога; CGRequest - показывает системный диалог и регистрирует
/// агент в System Settings -> Privacy -> Screen & System Audio Recording.
enum ScreenCapturePermission {
    /// Есть ли разрешение прямо сейчас (без диалога).
    static func has() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Гарантировать разрешение: если нет - показать системный диалог (один раз).
    /// Возвращает текущий статус. Вызывать при ВКЛЮЧЕНИИ тумблера, не на старте.
    @discardableResult
    static func ensure() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    /// Открыть системные настройки на разделе записи экрана (если пользователь отказал).
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
