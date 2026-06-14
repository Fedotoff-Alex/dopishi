import Foundation

/// Reconciler no-flicker (PERF-02): решает судьбу ПОКАЗАННОЙ подсказки при новом контексте.
///
/// Зачем: раньше каждый новый EditingContext безусловно гасил ghost (cancelAndHide), из-за чего
/// подсказка мигала на дубль-контекстах - Electron lag-poll перечитывает AX до ~405мс после
/// нажатия, а подсказка показывается после debounce ~350мс: poll-тик с тем же текстом гасил
/// только что показанный ghost. Reconciler различает: дубль (держать), набор начала подсказки
/// (сдвинуть, type-through), несовместимость (гасить - показывать неверный текст нельзя).
public enum SuggestionReconcile {
    public enum Decision: Equatable {
        /// Контекст не изменился (тот же текст, то же приложение) - ничего не делать:
        /// не гасить ghost, не перезапускать debounce. Геометрию каретки можно обновить.
        case unchanged
        /// Набрано начало показанной подсказки - сдвинуть ghost на остаток без перегенерации.
        case typeThrough(remaining: String)
        /// Набрана вся подсказка целиком - скрыть и записать typedThrough.
        case typedThroughAll
        /// Показанная подсказка несовместима с новым контекстом (расхождение набора,
        /// backspace, смена приложения) - погасить немедленно и идти обычным путём.
        case invalidated
        /// Подсказки не было - обычный путь (policy + debounce).
        case noSuggestion
    }

    /// previousPrefix - текст до каретки, для которого живёт текущее состояние (nil = первый
    /// контекст сессии). sameApp - совпал ли bundleId с предыдущим контекстом.
    /// shownSuggestion - текст показанной подсказки (nil/пусто = подсказки нет).
    public static func decide(previousPrefix: String?, newPrefix: String,
                              sameApp: Bool, shownSuggestion: String?) -> Decision {
        let suggestion = (shownSuggestion?.isEmpty == false) ? shownSuggestion! : nil

        // Смена приложения: с подсказкой - гасить немедленно (SC-2), без - обычный путь.
        guard sameApp else { return suggestion == nil ? .noSuggestion : .invalidated }

        if let prev = previousPrefix, prev == newPrefix {
            return .unchanged
        }

        guard let suggestion else { return .noSuggestion }
        guard let prev = previousPrefix else { return .invalidated }

        // Type-through: к старому префиксу дописано РОВНО начало подсказки.
        if newPrefix.count > prev.count, newPrefix.hasPrefix(prev) {
            let typed = String(newPrefix.dropFirst(prev.count))
            if suggestion.hasPrefix(typed) {
                let remaining = String(suggestion.dropFirst(typed.count))
                return remaining.isEmpty ? .typedThroughAll : .typeThrough(remaining: remaining)
            }
            // Стыковая терпимость: набран ОДИН пробел, подсказка начинается сразу со слова
            // (без ведущего пробела), а старый префикс пробелом не кончался - это тот же
            // стык слов, не расхождение. Держим подсказку как есть.
            if typed == " ", !prev.hasSuffix(" "),
               let first = suggestion.first, first.isLetter {
                return .typeThrough(remaining: suggestion)
            }
        }
        return .invalidated
    }
}
