import Foundation

public enum KeyAction: Equatable, Sendable {
    case suggest
    case accept           // Tab: следующее слово подсказки
    case acceptAll        // Shift+Tab: вся подсказка целиком
    case dismiss          // Esc: скрыть активную подсказку
    case undoCorrection   // Esc (без подсказки): откатить только что сделанную автоправку
    case undo
    case none
}

public struct KeyDecision: Equatable, Sendable {
    public let action: KeyAction
    public let swallow: Bool
    public init(action: KeyAction, swallow: Bool) {
        self.action = action
        self.swallow = swallow
    }
}

public enum KeyDecider {
    // Virtual keyCodes: J=38, Tab=48, Esc=53.
    public static func decideKeyDown(keyCode: Int, control: Bool, option: Bool,
                                     command: Bool = false, shift: Bool = false,
                                     suggestionActive: Bool,
                                     correctionUndoable: Bool = false) -> KeyDecision {
        if keyCode == 38, control, option {
            return KeyDecision(action: .suggest, swallow: true)
        }
        if keyCode == 48, suggestionActive {
            // Tab = следующее слово; Shift+Tab (ровно, без других модификаторов) = вся
            // подсказка. grave не используем - на RU-раскладке это буква ё. Прочие Tab при
            // активной подсказке дают accept (как было раньше).
            if shift, !control, !option, !command {
                return KeyDecision(action: .acceptAll, swallow: true)
            }
            return KeyDecision(action: .accept, swallow: true)
        }
        if keyCode == 53 {
            // Esc: при активной подсказке скрываем её; иначе, если только что была автоправка -
            // откатываем её. Без того и другого Esc проходит насквозь (не ломаем Esc приложения).
            if suggestionActive { return KeyDecision(action: .dismiss, swallow: true) }
            if correctionUndoable { return KeyDecision(action: .undoCorrection, swallow: true) }
            return KeyDecision(action: .none, swallow: false)
        }
        if keyCode == 6, control, option {
            return KeyDecision(action: .undo, swallow: true)
        }
        return KeyDecision(action: .none, swallow: false)
    }
}
