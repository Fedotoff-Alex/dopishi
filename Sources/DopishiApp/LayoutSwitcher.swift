import Carbon
import Foundation

/// Переключение клавиатурной раскладки на источник нужного языка через TIS.
enum LayoutSwitcher {
    /// Основной язык текущей раскладки ("ru"/"en"/...), если доступен.
    static func currentLanguage() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return primaryLanguage(of: src)
    }

    /// Выбрать раскладку, чей основной язык == language. Возвращает успех.
    @discardableResult
    static func selectLayout(language: String) -> Bool {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let cf = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return false }
        let count = CFArrayGetCount(cf)
        for i in 0..<count {
            let src = unsafeBitCast(CFArrayGetValueAtIndex(cf, i), to: TISInputSource.self)
            if primaryLanguage(of: src) == language, isSelectable(src) {
                return TISSelectInputSource(src) == noErr
            }
        }
        return false
    }

    private static func primaryLanguage(of src: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return nil }
        let arr = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue()
        guard CFArrayGetCount(arr) > 0 else { return nil }
        let langPtr = CFArrayGetValueAtIndex(arr, 0)
        let lang = unsafeBitCast(langPtr, to: CFString.self) as String
        return lang
    }

    private static func isSelectable(_ src: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }
}
