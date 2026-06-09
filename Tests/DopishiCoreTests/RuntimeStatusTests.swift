import Testing
@testable import DopishiCore

@Suite struct RuntimeStatusTests {
    private func granted() -> PermissionState { PermissionState(accessibility: true, inputMonitoring: true) }

    @Test func permissionsMissingShowsPermissionMessage() {
        let s = AppRuntimeStatus(permissions: PermissionState(accessibility: false, inputMonitoring: true),
                                 monitorRunning: false, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s).contains("Accessibility"))
    }
    @Test func monitorNotRunning() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: false, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "Допиши: монитор не запущен - перезапустите")
    }
    @Test func modelMissing() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: true, modelPresent: false)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "Допиши: модель не скачана")
        #expect(RuntimeStatusPresentation.needsModelDownload(s))
    }
    @Test func disabled() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: false, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "Допиши: выключено")
    }
    @Test func active() {
        let s = AppRuntimeStatus(permissions: granted(), monitorRunning: true, enabled: true, modelPresent: true)
        #expect(RuntimeStatusPresentation.menuTitle(for: s) == "Допиши: активно")
        #expect(!RuntimeStatusPresentation.needsModelDownload(s))
    }
}
