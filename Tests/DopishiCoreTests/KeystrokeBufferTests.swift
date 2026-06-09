import Testing
@testable import DopishiCore

@Suite struct KeystrokeBufferTests {
    @Test func emptyByDefault() {
        #expect(KeystrokeBuffer().text == "")
    }

    @Test func appending_concatenates_andReturnsNewBuffer() {
        let b0 = KeystrokeBuffer()
        let b1 = b0.appending("При")
        let b2 = b1.appending("вет")
        #expect(b0.text == "")          // исходный не изменился
        #expect(b2.text == "Привет")
    }

    @Test func backspacing_removesLastCharacter() {
        #expect(KeystrokeBuffer().appending("Привет").backspacing().text == "Приве")
    }

    @Test func backspacing_onEmpty_isNoop() {
        #expect(KeystrokeBuffer().backspacing().text == "")
    }

    @Test func reset_clears() {
        #expect(KeystrokeBuffer().appending("abc").reset().text == "")
    }

    @Test func capsToMaxLength_keepingSuffix() {
        #expect(KeystrokeBuffer(maxLength: 3).appending("abcdef").text == "def")
    }
}
