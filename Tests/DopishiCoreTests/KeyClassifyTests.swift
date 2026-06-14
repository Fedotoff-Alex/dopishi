import Testing
@testable import DopishiCore

/// Классификация клавиш для InputMonitor: навигация двигает каретку (сброс буфера),
/// функциональные клавиши не должны попадать в keystroke-буфер как «набранный текст».
/// Баг до фикса: стрелки давали didType("\u{F702}") - буфер загрязнялся functional-символом,
/// freshness-проверка (precedingText.hasSuffix(буфер)) вечно false, подсказки молчали до клика.
@Suite struct KeyClassifyTests {

    // MARK: - навигация: каретка сдвинулась

    @Test func arrowsAreCaretNavigation() {
        #expect(KeyClassify.isCaretNavigation(keyCode: 123))   // left
        #expect(KeyClassify.isCaretNavigation(keyCode: 124))   // right
        #expect(KeyClassify.isCaretNavigation(keyCode: 125))   // down
        #expect(KeyClassify.isCaretNavigation(keyCode: 126))   // up
    }

    @Test func homeEndPageKeysAreCaretNavigation() {
        #expect(KeyClassify.isCaretNavigation(keyCode: 115))   // home
        #expect(KeyClassify.isCaretNavigation(keyCode: 119))   // end
        #expect(KeyClassify.isCaretNavigation(keyCode: 116))   // page up
        #expect(KeyClassify.isCaretNavigation(keyCode: 121))   // page down
    }

    @Test func enterKeysAreCaretNavigation() {
        // Enter = отправка в чатах (поле чистится) или newline (каретка съехала).
        // Без перечитки после Enter ghost висел бы над пустым полем.
        #expect(KeyClassify.isCaretNavigation(keyCode: 36))    // return
        #expect(KeyClassify.isCaretNavigation(keyCode: 76))    // keypad enter
    }

    @Test func letterKeysAreNotNavigation() {
        #expect(!KeyClassify.isCaretNavigation(keyCode: 0))    // a
        #expect(!KeyClassify.isCaretNavigation(keyCode: 49))   // space
        #expect(!KeyClassify.isCaretNavigation(keyCode: 51))   // backspace
    }

    // MARK: - функциональные символы: не текст

    @Test func functionKeyCharsDetected() {
        #expect(KeyClassify.isFunctionKeyChars("\u{F700}"))    // up arrow char
        #expect(KeyClassify.isFunctionKeyChars("\u{F702}"))    // left arrow char
        #expect(KeyClassify.isFunctionKeyChars("\u{F704}"))    // F1
        #expect(KeyClassify.isFunctionKeyChars("\u{F72C}"))    // page up char
    }

    @Test func normalTextIsNotFunctionChars() {
        #expect(!KeyClassify.isFunctionKeyChars("а"))
        #expect(!KeyClassify.isFunctionKeyChars("q"))
        #expect(!KeyClassify.isFunctionKeyChars(" "))
        #expect(!KeyClassify.isFunctionKeyChars("ё"))
        #expect(!KeyClassify.isFunctionKeyChars(""))
    }
}
