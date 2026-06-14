import Foundation

/// Причина, по которой автоподсказка НЕ показывается в текущем поле. Человекочитаемый
/// `label` идёт в панель диагностики - чтобы было видно «почему не работает».
public enum SuggestionRefusal: String, Sendable, Equatable {
    case disabled            // мастер-тумблер выключен
    case secureField         // защищённое поле (пароль) - не читаем и не подсказываем
    case noCaretGeometry     // нет позиции каретки (tier textOnly/none) - некуда рисовать призрак
    case appExcluded         // приложение в списке исключений
    case appNoAutocomplete   // профиль приложения молчит (терминал/редактор кода)
    case belowMinChars       // слишком мало набрано (меньше порога)
    case emptyText           // нет текста до каретки
    case staleContext        // AX-текст отстаёт от клавиатуры (лаг Electron) - ждём свежий
    case midText             // каретка в середине текста - ghost лёг бы поверх следующего

    public var label: String {
        switch self {
        case .disabled: return "Выключено мастер-тумблером"
        case .secureField: return "Защищённое поле (пароль) - подсказки отключены"
        case .noCaretGeometry: return "Нет позиции каретки (приложение не отдаёт геометрию)"
        case .appExcluded: return "Приложение в списке исключений"
        case .appNoAutocomplete: return "Профиль приложения молчит (терминал/редактор кода)"
        case .belowMinChars: return "Слишком мало набрано (ниже порога)"
        case .emptyText: return "Нет текста до каретки"
        case .staleContext: return "Текст AX отстаёт от набора (лаг приложения) - ждём"
        case .midText: return "Каретка в середине текста - подсказка легла бы поверх"
        }
    }
}

/// Что произошло с последним запросом подсказки. Для панели диагностики.
public enum SuggestionOutcome: Sendable, Equatable {
    case refused(SuggestionRefusal)
    case correction   // показано исправление опечатки (зелёным)
    case emoji        // показано эмодзи-предложение
    case snippet      // показан сниппет (":sig" -> текст)
    case completion   // показано дописывание от модели
    case modelEmpty   // модель не дала продолжения

    public var label: String {
        switch self {
        case .refused(let r): return r.label
        case .correction: return "Показано: исправление опечатки"
        case .emoji: return "Показано: эмодзи"
        case .snippet: return "Показано: сниппет"
        case .completion: return "Показано: дописывание (подсказка)"
        case .modelEmpty: return "Модель не дала продолжения"
        }
    }
}

/// Результат гейта автоподсказки: показывать или отказать с причиной.
public enum SuggestionGateResult: Sendable, Equatable {
    case allow
    case refuse(SuggestionRefusal)
}
