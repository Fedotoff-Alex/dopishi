import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct CaretGeometryTests {
    @Test func midScreen() {
        let rect = CGRect(x: 100, y: 50, width: 2, height: 16) // maxY = 66
        let p = CaretGeometry.cocoaOrigin(axScreenRect: rect, primaryScreenHeight: 1000)
        #expect(p.x == 100)
        #expect(p.y == 934)            // 1000 - 66
    }
    @Test func topOfScreen() {
        let rect = CGRect(x: 10, y: 0, width: 2, height: 16) // maxY = 16
        let p = CaretGeometry.cocoaOrigin(axScreenRect: rect, primaryScreenHeight: 1000)
        #expect(p.y == 984)
    }
    @Test func bottomOfScreen() {
        let rect = CGRect(x: 10, y: 984, width: 2, height: 16) // maxY = 1000
        let p = CaretGeometry.cocoaOrigin(axScreenRect: rect, primaryScreenHeight: 1000)
        #expect(p.y == 0)
    }
    @Test func keepsX() {
        let rect = CGRect(x: 42.5, y: 10, width: 2, height: 16)
        let p = CaretGeometry.cocoaOrigin(axScreenRect: rect, primaryScreenHeight: 800)
        #expect(p.x == 42.5)
    }
}
