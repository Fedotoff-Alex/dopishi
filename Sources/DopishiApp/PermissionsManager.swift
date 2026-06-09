import AppKit
import ApplicationServices
import CoreGraphics
import DopishiCore

enum PermissionsManager {
    // --- Accessibility ---
    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный prompt и ведёт пользователя в настройки.
    static func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt - C extern var, не Sendable в Swift 6.
        // Используем строковое значение напрямую (публичный AX API).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // --- Input Monitoring (listen events) ---
    static func hasInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    // --- Текущее состояние единым объектом ---
    static func current() -> PermissionState {
        PermissionState(accessibility: hasAccessibility(),
                        inputMonitoring: hasInputMonitoring())
    }

    // --- Deeplinks в System Settings ---
    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
