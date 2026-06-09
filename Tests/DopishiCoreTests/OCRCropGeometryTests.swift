import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct OCRCropGeometryTests {

    // Окно 1000x1000pt @(100,50), изображение 1600x1600px (scale 1.6). Каретка внизу по центру:
    // полоса 800pt над кареткой, ширина = ширине окна (1000 < 1020). Дно полосы у верха каретки.
    @Test func chatLikeCaretAtBottomBandAbove() {
        let plan = OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 600, y: 1000, width: 0, height: 20),
            windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 1000),
            imageWidth: 1600, imageHeight: 1600)
        #expect(plan?.cropRectPx == CGRect(x: 0, y: 240, width: 1600, height: 1280))
        #expect(plan?.caretInCropPx == CGPoint(x: 800, y: 1296))
    }

    // Каретка у верха окна: предложенный верх полосы уезжает выше окна -> клемп к верху окна (y=0px).
    @Test func caretNearTopClampsBandToWindowTop() {
        let plan = OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 600, y: 60, width: 0, height: 20),
            windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 1000),
            imageWidth: 1600, imageHeight: 1600)
        #expect(plan?.cropRectPx == CGRect(x: 0, y: 0, width: 1600, height: 1280))
        #expect(plan?.caretInCropPx == CGPoint(x: 800, y: 32))
    }

    // Узкое короткое окно (500x600 < 1020 ширины, < 800 высоты): полоса = всё окно.
    @Test func narrowShortWindowCapturesWholeWindow() {
        let plan = OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 250, y: 580, width: 0, height: 20),
            windowFrame: CGRect(x: 0, y: 0, width: 500, height: 600),
            imageWidth: 1000, imageHeight: 1200)
        #expect(plan?.cropRectPx == CGRect(x: 0, y: 0, width: 1000, height: 1200))
        #expect(plan?.caretInCropPx == CGPoint(x: 500, y: 1180))
    }

    // Каретка у правого края широкого окна: X клемпится к (maxX - targetW).
    @Test func caretNearRightEdgeClampsX() {
        let plan = OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 1950, y: 1400, width: 0, height: 20),
            windowFrame: CGRect(x: 0, y: 0, width: 2000, height: 1500),
            imageWidth: 1600, imageHeight: 1200)
        #expect(plan?.cropRectPx == CGRect(x: 784, y: 480, width: 816, height: 640))
        #expect(plan?.caretInCropPx == CGPoint(x: 776, y: 648))
    }

    // Stale-каретка далеко ниже окна -> nil (откат на OCR всего окна, а не кривой кроп).
    @Test func caretFarBelowWindowReturnsNil() {
        #expect(OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 600, y: 5000, width: 0, height: 20),
            windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 1000),
            imageWidth: 1600, imageHeight: 1600) == nil)
    }

    @Test func caretFarAboveWindowReturnsNil() {
        #expect(OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 600, y: -3000, width: 0, height: 20),
            windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 1000),
            imageWidth: 1600, imageHeight: 1600) == nil)
    }

    // Каретка у самого нижнего края (legit) - план строится (gate не ложно-срабатывает).
    @Test func caretAtBottomEdgeStillPlans() {
        #expect(OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 600, y: 1045, width: 0, height: 4),
            windowFrame: CGRect(x: 100, y: 50, width: 1000, height: 1000),
            imageWidth: 1600, imageHeight: 1600) != nil)
    }

    @Test func degenerateInputsReturnNil() {
        #expect(OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 0, y: 0, width: 0, height: 10),
            windowFrame: CGRect(x: 0, y: 0, width: 0, height: 100),
            imageWidth: 100, imageHeight: 100) == nil)
        #expect(OCRCropGeometry.plan(
            caretScreenRect: CGRect(x: 0, y: 0, width: 0, height: 10),
            windowFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageWidth: 0, imageHeight: 100) == nil)
    }
}
