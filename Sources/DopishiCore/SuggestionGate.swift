import Foundation

public enum SuggestionGate {
    /// Подсказку имеет смысл показывать, только если после обрезки пробелов/переводов строк
    /// остаётся непустой текст.
    public static func isPresentable(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
