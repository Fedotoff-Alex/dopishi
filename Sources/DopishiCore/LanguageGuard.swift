import Foundation

public enum LanguageGuard {
    /// Разрешить ли показ подсказки. Подавляем латинскую подсказку, когда контекст кириллический
    /// (типичный англоязычный дрейф базовых моделей). Для русского кириллического контекста
    /// также режем явный украинский дрейф, но не вмешиваемся, если сам контекст уже украинский.
    public static func allows(suggestion: String, givenContext context: String) -> Bool {
        let contextTail = String(context.suffix(40))
        guard TextScriptDetector.dominant(of: contextTail) == .cyrillic else { return true }
        guard TextScriptDetector.dominant(of: suggestion) != .latin else { return false }

        let contextLooksUkrainian = containsUkrainianMarkers(contextTail)
        if !contextLooksUkrainian, containsUkrainianMarkers(suggestion) {
            return false
        }
        return true
    }

    private static let ukrainianMarkerWords: Set<String> = [
        "але", "від", "після", "це", "що", "щоб", "якщо"
    ]

    private static func containsUkrainianMarkers(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0404, 0x0454, // Є є
                 0x0406, 0x0456, // І і
                 0x0407, 0x0457, // Ї ї
                 0x0490, 0x0491: // Ґ ґ
                return true
            default:
                break
            }
        }
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains { ukrainianMarkerWords.contains($0) }
    }
}
