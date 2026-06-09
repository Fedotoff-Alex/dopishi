import Foundation

public enum HUDRedaction {
    /// Маскированная сводка набранного текста для debug-HUD: длина + скрипт, без реальных символов.
    public static func summarize(_ text: String) -> String {
        guard !text.isEmpty else { return "пусто" }
        let script: String
        switch TextScriptDetector.dominant(of: text) {
        case .cyrillic: script = "кириллица"
        case .latin: script = "латиница"
        case .neutral: script = "без букв"
        }
        return "\(text.count) симв., \(script)"
    }
}
