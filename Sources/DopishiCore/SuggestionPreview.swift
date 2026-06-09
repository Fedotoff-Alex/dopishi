import Foundation

public enum SuggestionPreview {
    /// Можно ли уже показать промежуточную подсказку, не дожидаясь полной генерации.
    /// Показываем только стабильную границу: модель уже закрыла первое слово пробелом
    /// или пунктуацией. Это снижает ощущаемую задержку без показа полуслова.
    public static func isStable(_ text: String) -> Bool {
        guard SuggestionGate.isPresentable(text), let last = text.last else { return false }
        return last.isWhitespace || last.isPunctuation || last.isSymbol
    }
}
