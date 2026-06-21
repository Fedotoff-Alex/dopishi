import Foundation

public struct PermissionState: Sendable, Equatable {
    public let accessibility: Bool
    public let inputMonitoring: Bool

    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var allGranted: Bool { accessibility && inputMonitoring }

    /// Список недостающих прав. Имена технические (Accessibility / Input Monitoring) - НЕ
    /// переводятся (совпадают с названиями системных разрешений macOS). App собирает финальную
    /// строку статуса через L.tr("status.needPermissions", missingPermissions.joined(", ")).
    public var missingPermissions: [String] {
        var missing: [String] = []
        if !accessibility { missing.append("Accessibility") }
        if !inputMonitoring { missing.append("Input Monitoring") }
        return missing
    }
}

public enum StatusPresentation {
    /// Стабильный id заголовка статус-меню по правам; локализуется в App через L.tr (D-11, Open Q3).
    /// При недостающих правах App дополняет id списком state.missingPermissions.
    public static func menuTitle(for state: PermissionState) -> String {
        state.allGranted ? "status.active" : "status.needPermissions"
    }

    public static func symbolName(for state: PermissionState) -> String {
        state.allGranted ? "text.cursor" : "exclamationmark.triangle"
    }
}
