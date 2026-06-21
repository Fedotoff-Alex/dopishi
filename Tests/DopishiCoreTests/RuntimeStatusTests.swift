import Testing
@testable import DopishiCore

@Suite struct RuntimeStatusTests {
    private func granted() -> PermissionState { PermissionState(accessibility: true, inputMonitoring: true) }

    // D-11/Open Q3: menuTitle отдаёт стабильный id (App локализует через L.tr), не русский текст.
    // Семантика «какой статус при каком state» сохранена.
    @Test func permissionsMissingDelegatesToPermissionStatusId() {
        let s = AppRuntimeStatus(permissions: PermissionState(accessibility: false, inputMonitoring: true),
                                 monitorRunning: false, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "status.needPermissions")
    }
    @Test func monitorNotRunning() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: false, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "status.monitorStopped")
    }
    @Test func modelMissing() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: true, modelPresent: false)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "status.noModel")
        #expect(RuntimeStatusPresentation.needsModelDownload(s))
    }
    @Test func disabled() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: false, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "status.disabled")
    }
    @Test func active() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "status.active")
        #expect(!RuntimeStatusPresentation.needsModelDownload(s))
    }
}
