import Foundation

public enum Script: String, Sendable, Equatable {
    case cyrillic, latin, neutral
}

public enum TextScriptDetector {
    /// Доминирующий скрипт по буквенным символам. neutral, если букв нет.
    public static func dominant(of text: String) -> Script {
        var cyr = 0, lat = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: cyr += 1                  // кириллица
            case 0x41...0x5A, 0x61...0x7A: lat += 1         // латиница A-Z a-z
            default: break
            }
        }
        if cyr == 0 && lat == 0 { return .neutral }
        return cyr >= lat ? .cyrillic : .latin
    }
}
