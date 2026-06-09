import Foundation

/// Язык для орфо-проверки - строго ru/en по доминирующему скрипту слова.
/// Для нейтральных (цифры/пунктуация/прочее) и иных скриптов - nil (не исправляем).
public enum SpellLanguage {
    public static func code(for word: String) -> String? {
        switch TextScriptDetector.dominant(of: word) {
        case .cyrillic: return "ru"
        case .latin: return "en"
        case .neutral: return nil
        }
    }
}
