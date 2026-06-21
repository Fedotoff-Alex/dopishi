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

    // D-11/Open Q3: menuTitle отдаёт стабильный id (App локализует через L.tr); список недостающих
    // прав - в отдельном свойстве missingPermissions (App собирает финальную строку).
    @Test func menuTitle_activeId_whenAllGranted() {
        let s = PermissionState(accessibility: true, inputMonitoring: true)
        #expect(StatusPresentation.menuTitle(for: s) == "status.active")
        #expect(s.missingPermissions.isEmpty)
    }

    @Test func menuTitle_needPermissionsId_andListsMissing() {
        let s = PermissionState(accessibility: false, inputMonitoring: false)
        #expect(StatusPresentation.menuTitle(for: s) == "status.needPermissions")
        #expect(s.missingPermissions == ["Accessibility", "Input Monitoring"])
    }

    @Test func missingPermissions_listsOnlyMissing() {
        #expect(PermissionState(accessibility: true, inputMonitoring: false).missingPermissions == ["Input Monitoring"])
        #expect(PermissionState(accessibility: false, inputMonitoring: true).missingPermissions == ["Accessibility"])
    }

    @Test func symbolName_dependsOnGrant() {
        #expect(StatusPresentation.symbolName(for: PermissionState(accessibility: true, inputMonitoring: true)) == "text.cursor")
        #expect(StatusPresentation.symbolName(for: PermissionState(accessibility: false, inputMonitoring: true)) == "exclamationmark.triangle")
    }
}
