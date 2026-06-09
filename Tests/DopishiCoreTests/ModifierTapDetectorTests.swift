import Testing
@testable import DopishiCore

@Suite struct ModifierTapDetectorTests {
    @Test func cleanTapFires() {
        var d = ModifierTapDetector()
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: false)).0
        let (_, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false))
        #expect(fired)
    }

    @Test func optionPlusKeyDoesNotFire() {
        var d = ModifierTapDetector()
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: false)).0
        d = d.feeding(.keyDown).0
        let (_, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false))
        #expect(!fired)
    }

    @Test func optionWithOtherModifierDoesNotFire() {
        var d = ModifierTapDetector()
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: false)).0
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: true)).0
        let (_, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false))
        #expect(!fired)
    }

    @Test func optionPlusMouseDoesNotFire() {
        var d = ModifierTapDetector()
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: false)).0
        d = d.feeding(.mouseDown).0
        let (_, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false))
        #expect(!fired)
    }

    @Test func loneOtherModifierDoesNotFire() {
        var d = ModifierTapDetector()
        let (next, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: true))
        d = next
        #expect(!fired)
        let (_, fired2) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false))
        #expect(!fired2)
    }

    @Test func rollOffOtherModifierDoesNotFire() {
        // Держим Shift, жмём Option (Shift ещё зажат), отпускаем Shift (Option зажат), отпускаем Option.
        // Это НЕ чистый тап - не должно сработать.
        var d = ModifierTapDetector()
        d = d.feeding(.flagsChanged(optionDown: false, otherModifiers: true)).0  // Shift down
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: true)).0   // Option down, Shift held
        d = d.feeding(.flagsChanged(optionDown: true, otherModifiers: false)).0  // Shift up, Option held
        let (_, fired) = d.feeding(.flagsChanged(optionDown: false, otherModifiers: false)) // Option up
        #expect(!fired)
    }
}
