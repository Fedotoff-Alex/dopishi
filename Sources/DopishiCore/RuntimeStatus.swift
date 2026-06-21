import Foundation

public struct AppRuntimeStatus: Sendable, Equatable {
    public let permissions: PermissionState
    public let monitorRunning: Bool
    public let enabled: Bool
    public let modelPresent: Bool

    public init(permissions: PermissionState, monitorRunning: Bool, enabled: Bool, modelPresent: Bool) {
        self.permissions = permissions
        self.monitorRunning = monitorRunning
        self.enabled = enabled
        self.modelPresent = modelPresent
    }
}

public enum RuntimeStatusPresentation {
    /// Стабильный id заголовка пункта меню по реальной готовности (а не только по правам);
    /// локализуется в App через L.tr (D-11, Open Q3). При недостающих правах делегирует
    /// в StatusPresentation (тот тоже отдаёт id).
    public static func menuTitle(for s: AppRuntimeStatus) -> String {
        if !s.permissions.allGranted { return StatusPresentation.menuTitle(for: s.permissions) }
        if !s.monitorRunning { return "status.monitorStopped" }
        if !s.modelPresent { return "status.noModel" }
        if !s.enabled { return "status.disabled" }
        return "status.active"
    }

    /// Нужно ли показывать пункт «скачать модель» (права есть, модели нет).
    public static func needsModelDownload(_ s: AppRuntimeStatus) -> Bool {
        s.permissions.allGranted && !s.modelPresent
    }
}
