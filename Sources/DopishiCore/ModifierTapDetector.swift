import Foundation

/// Сигнал ввода для распознавания «чистого тапа» модификатора.
public enum ModifierTapSignal: Equatable, Sendable {
    /// Изменились модификаторы: зажат ли Option и присутствуют ли другие (Ctrl/Cmd/Shift).
    case flagsChanged(optionDown: Bool, otherModifiers: Bool)
    case keyDown
    case mouseDown
}

/// Иммутабельная стейт-машина: распознаёт одиночный чистый тап Option
/// (Option нажали и отпустили, ничего другого за время удержания не нажимали).
/// Стиль как у KeystrokeBuffer - вместо мутации возвращает новое значение.
public struct ModifierTapDetector: Equatable, Sendable {
    public let armed: Bool
    /// Был ли Option зажат на предыдущем шаге (для определения фронта нажатия).
    public let optionWasDown: Bool

    public init(armed: Bool = false, optionWasDown: Bool = false) {
        self.armed = armed
        self.optionWasDown = optionWasDown
    }

    /// Возвращает (новое состояние, сработал ли тап ровно сейчас).
    public func feeding(_ signal: ModifierTapSignal) -> (ModifierTapDetector, Bool) {
        switch signal {
        case .flagsChanged(let optionDown, let other):
            if optionDown {
                let rising = !optionWasDown
                // Взводимся только на ФРОНТЕ нажатия Option и без других модификаторов.
                // Если Option уже был зажат - не перевзводимся (иначе отпускание другого
                // модификатора посреди удержания дало бы ложный тап).
                let nowArmed = rising ? !other : (armed && !other)
                return (ModifierTapDetector(armed: nowArmed, optionWasDown: true), false)
            }
            // Option отпущен - тап, если оставались взведены и Option реально был зажат.
            let fired = armed && optionWasDown
            return (ModifierTapDetector(armed: false, optionWasDown: false), fired)
        case .keyDown, .mouseDown:
            // Во время удержания нажали ещё что-то - снимаем взвод (Option может оставаться зажат).
            return (ModifierTapDetector(armed: false, optionWasDown: optionWasDown), false)
        }
    }
}
