import AppKit
import CoreGraphics
import DopishiCore

enum InputEvent: Equatable {
    case didType(String)
    case backspace
    case caretMayHaveMoved
    case suggestRequested
    case acceptRequested
    case acceptAllRequested
    case undoCorrectionRequested
    case dismissRequested
    case undoRequested
    case layoutSwitchRequested
}

final class InputMonitor {
    var onEvent: ((InputEvent) -> Void)?

    /// Флаг для KeyDecider: есть ли активная подсказка.
    /// Устанавливается на главном потоке (per tap contract).
    var suggestionActive = false

    /// Флаг для KeyDecider: только что была автоправка, которую Esc может откатить.
    /// Ставится на границе слова при автокоррекции, гасится на следующем нажатии.
    var correctionUndoable = false

    /// Распознаёт одиночный тап Option для ручного переключения раскладки.
    private var tapDetector = ModifierTapDetector()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Возвращает false, если не удалось создать tap (обычно - нет прав).
    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = monitor.handle(type: type, event: event)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        // КОНТРАКТ потокобезопасности: источник вешаем на ГЛАВНЫЙ runloop, поэтому
        // callback (а значит handle и onEvent) исполняется на главном потоке. Весь доступ
        // к eventTap/runLoopSource/onEvent рассчитан на главный поток. Если tap когда-нибудь
        // унесут на отдельный поток - появится гонка (поймает dispatchPrecondition в handle).
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    @discardableResult
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))  // см. контракт в start()
        if event.getIntegerValueField(.eventSourceUserData) == Injector.syntheticMarker {
            return false   // наше синтетическое событие - пропускаем, не эмитим
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            tapDetector = tapDetector.feeding(.mouseDown).0
            onEvent?(.caretMayHaveMoved)
            return false
        case .flagsChanged:
            // Загрязнители тапа - только Control/Command/Shift. Fn и CapsLock сознательно
            // НЕ учитываем: включённый CapsLock иначе блокировал бы тап навсегда.
            let optionDown = event.flags.contains(.maskAlternate)
            let other = !event.flags
                .intersection([.maskControl, .maskCommand, .maskShift])
                .isEmpty
            let (next, fired) = tapDetector.feeding(
                .flagsChanged(optionDown: optionDown, otherModifiers: other))
            tapDetector = next
            if fired { onEvent?(.layoutSwitchRequested) }
            return false
        case .keyDown:
            tapDetector = tapDetector.feeding(.keyDown).0
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let decision = KeyDecider.decideKeyDown(
                keyCode: keyCode,
                control: event.flags.contains(.maskControl),
                option: event.flags.contains(.maskAlternate),
                command: event.flags.contains(.maskCommand),
                shift: event.flags.contains(.maskShift),
                suggestionActive: suggestionActive,
                correctionUndoable: correctionUndoable
            )
            switch decision.action {
            case .suggest:         onEvent?(.suggestRequested)
            case .accept:          onEvent?(.acceptRequested)
            case .acceptAll:       onEvent?(.acceptAllRequested)
            case .undoCorrection:  onEvent?(.undoCorrectionRequested)
            case .dismiss:         onEvent?(.dismissRequested)
            case .undo:    onEvent?(.undoRequested)
            case .none:
                if keyCode == 51 {
                    onEvent?(.backspace)
                } else if KeyClassify.isCaretNavigation(keyCode: keyCode) {
                    // Стрелки/Home/End/PageUp/PageDown двигают каретку - сбрасываем
                    // фолбэк-буфер, как при клике. Раньше их functional-символ (U+F70x)
                    // уходил в didType и загрязнял буфер: freshness вечно false,
                    // подсказки молчали до следующего клика.
                    onEvent?(.caretMayHaveMoved)
                } else if let ns = NSEvent(cgEvent: event),
                          let chars = ns.characters,
                          !chars.isEmpty,
                          !KeyClassify.isFunctionKeyChars(chars),
                          chars.first.map({ !$0.isNewline }) == true {
                    onEvent?(.didType(chars))
                }
            }
            return decision.swallow
        default:
            return false
        }
    }
}
