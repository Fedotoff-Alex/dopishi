import Foundation

/// Управление глобальными настройками автоисправления текста macOS (NSGlobalDomain).
/// Системная автокоррекция орфографии конфликтует с авто-заменой Dopishi: оба правят поле
/// почти одновременно (наш backspace+вставка против системной замены) -> склейка слов.
/// При включённой опции гасим системную автокоррекцию и автодополнение.
/// ВАЖНО: изменение применяется к приложениям при следующем чтении настройки - обычно
/// после перезапуска целевого приложения (уже открытое поле может не подхватить сразу).
enum SystemTextCorrection {
    private static let spellingKey = "NSAutomaticSpellingCorrectionEnabled"
    private static let completionKey = "NSAutomaticTextCompletionEnabled"

    /// Включена ли системная автокоррекция орфографии сейчас (системный дефолт - включена).
    static func isSystemAutocorrectOn() -> Bool {
        readGlobalBool(spellingKey) ?? true
    }

    /// Применить желаемое состояние: disabled=true гасит системное, false возвращает.
    static func apply(disabled: Bool) {
        if disabled {
            writeGlobalBool(spellingKey, false)
            writeGlobalBool(completionKey, false)
        } else {
            writeGlobalBool(spellingKey, true)
            writeGlobalBool(completionKey, true)
        }
    }

    private static func readGlobalBool(_ key: String) -> Bool? {
        guard let v = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) else {
            return nil
        }
        if CFGetTypeID(v) == CFBooleanGetTypeID() {
            // swiftlint:disable:next force_cast
            return CFBooleanGetValue((v as! CFBoolean))
        }
        return (v as? NSNumber)?.boolValue
    }

    private static func writeGlobalBool(_ key: String, _ value: Bool) {
        CFPreferencesSetValue(
            key as CFString,
            (value ? kCFBooleanTrue : kCFBooleanFalse),
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}
