import Foundation

/// Классификация клавиш для InputMonitor (чистая логика, тестируется без CGEvent).
///
/// Зачем: стрелки и прочие функциональные клавиши приходят в keyDown с characters из
/// приватного диапазона Apple (U+F700-U+F8FF). Если пропустить их в didType, они попадают
/// в keystroke-буфер как «набранный текст» - буфер перестаёт быть суффиксом AX-текста,
/// freshness-проверка вечно false, и подсказки молчат до следующего клика (сброса буфера).
public enum KeyClassify {
    /// Клавиши, после которых каретка/состояние поля меняются: стрелки, Home/End,
    /// PageUp/PageDown, Return/Enter. Для них правильное событие - caretMayHaveMoved
    /// (сброс фолбэк-буфера + перечитка AX), не didType.
    /// Enter критичен для чатов: отправка чистит поле, и без перечитки ghost-подсказка
    /// зависала бы над пустым полем до следующего ввода.
    public static func isCaretNavigation(keyCode: Int) -> Bool {
        switch keyCode {
        case 123, 124, 125, 126,   // left, right, down, up
             115, 119,             // home, end
             116, 121,             // page up, page down
             36, 76:               // return, keypad enter
            return true
        default:
            return false
        }
    }

    /// Строка состоит из functional-key символа (приватный диапазон U+F700-U+F8FF):
    /// F1-F12, стрелки и т.п. Такое не текст - в буфер не писать.
    public static func isFunctionKeyChars(_ chars: String) -> Bool {
        guard let first = chars.unicodeScalars.first else { return false }
        return (0xF700...0xF8FF).contains(first.value)
    }
}
