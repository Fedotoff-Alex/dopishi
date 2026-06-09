import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct EditingContextTests {
    let rect = CGRect(x: 10, y: 20, width: 1, height: 16)

    @Test func secureField_yieldsEmptyNoneContext() {
        let ctx = EditingContextBuilder.build(
            axText: "secretpassword", fallbackText: "secretpassword",
            caretRect: rect, appBundleId: "com.app", isSecure: true)
        #expect(ctx.precedingText == "")
        #expect(ctx.caretScreenRect == nil)
        #expect(ctx.capability == .none)
        #expect(ctx.isSecure == true)
    }

    @Test func prefersAXText_overFallback() {
        let ctx = EditingContextBuilder.build(
            axText: "из AX", fallbackText: "из буфера",
            caretRect: rect, appBundleId: "com.app", isSecure: false)
        #expect(ctx.precedingText == "из AX")
        #expect(ctx.capability == .full)
        #expect(ctx.caretScreenRect == rect)
    }

    @Test func fallbackText_whenAXNil() {
        let ctx = EditingContextBuilder.build(
            axText: nil, fallbackText: "из буфера",
            caretRect: nil, appBundleId: "com.app", isSecure: false)
        #expect(ctx.precedingText == "из буфера")
        #expect(ctx.capability == .textOnly)
        #expect(ctx.caretScreenRect == nil)
    }

    @Test func none_whenNoTextAnywhere() {
        let ctx = EditingContextBuilder.build(
            axText: nil, fallbackText: "",
            caretRect: rect, appBundleId: nil, isSecure: false)
        #expect(ctx.capability == .none)
        #expect(ctx.caretScreenRect == nil)  // rect отбрасывается, т.к. тир не .full
    }
}
