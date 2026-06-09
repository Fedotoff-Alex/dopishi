import Testing
@testable import DopishiCore

@Suite struct PermissionStateTests {
    @Test func allGranted_whenBothTrue() {
        #expect(PermissionState(accessibility: true, inputMonitoring: true).allGranted)
    }

    @Test func notGranted_whenOneMissing() {
        #expect(!PermissionState(accessibility: true, inputMonitoring: false).allGranted)
        #expect(!PermissionState(accessibility: false, inputMonitoring: true).allGranted)
    }

    @Test func menuTitle_active_whenAllGranted() {
        let s = PermissionState(accessibility: true, inputMonitoring: true)
        #expect(StatusPresentation.menuTitle(for: s) == "Допиши: активно")
    }

    @Test func menuTitle_listsMissing() {
        let s = PermissionState(accessibility: false, inputMonitoring: false)
        #expect(StatusPresentation.menuTitle(for: s) == "Допиши: нужны разрешения (Accessibility, Input Monitoring)")
    }

    @Test func symbolName_dependsOnGrant() {
        #expect(StatusPresentation.symbolName(for: PermissionState(accessibility: true, inputMonitoring: true)) == "text.cursor")
        #expect(StatusPresentation.symbolName(for: PermissionState(accessibility: false, inputMonitoring: true)) == "exclamationmark.triangle")
    }
}
