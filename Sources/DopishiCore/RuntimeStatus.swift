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
    /// Заголовок пункта меню по реальной готовности (а не только по правам).
    public static func menuTitle(for s: AppRuntimeStatus) -> String {
        if !s.permissions.allGranted { return StatusPresentation.menuTitle(for: s.permissions) }
        if !s.monitorRunning { return "Допиши: монитор не запущен - перезапустите" }
        if !s.modelPresent { return "Допиши: модель не скачана" }
        if !s.enabled { return "Допиши: выключено" }
        return "Допиши: активно"
    }

    /// Нужно ли показывать пункт «скачать модель» (права есть, модели нет).
    public static func needsModelDownload(_ s: AppRuntimeStatus) -> Bool {
        s.permissions.allGranted && !s.modelPresent
    }
}
