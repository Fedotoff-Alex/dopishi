import AppKit
import CoreGraphics

/// Вставляет/удаляет текст в текущем сфокусированном поле через синтез клавиатурных событий.
/// Все синтетические события помечаются syntheticMarker, чтобы наш InputMonitor их игнорировал
/// (иначе авто-замена раскладки/орфографии зациклится на собственном выводе).
enum Injector {
    /// Маркер на поле userData синтетических событий.
    static let syntheticMarker: Int64 = 0x444F50 // "DOP"

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(text.utf16)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            down.post(tap: .cgSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            up.post(tap: .cgSessionEventTap)
        }
    }

    /// Удалить `count` символов назад (Backspace, virtualKey 51).
    static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true) {
                down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false) {
                up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                up.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// Заменить последнее набранное слово: удалить deleteCount символов и вставить replacement.
    static func replaceLastWord(deleteCount: Int, with replacement: String) {
        deleteBackward(deleteCount)
        insert(replacement)
    }

    /// Заменить активное выделение содержимым replacement через буфер обмена (Cmd+V).
    /// Почему не insert: keyboardSetUnicodeString надёжно вставляет только короткую строку,
    /// длинную фразу обрезает до первого слова. Cmd+V вставляет любую длину и сам заменяет
    /// выделение. Буфер пользователя сохраняем и возвращаем после вставки.
    static func replaceSelection(with replacement: String) {
        pasteReplace(with: replacement)
    }

    /// Вставка через системный буфер обмена + синтетический Cmd+V. Прежнее содержимое
    /// буфера (строка) восстанавливается с задержкой, после того как вставка применилась.
    static func pasteReplace(with text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        let saved = snapshot(pb)            // полный снимок: все items и все типы (не только строка)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChangeCount = pb.changeCount   // счётчик после нашей записи (Cmd+V читает, не меняет его)

        // Полная последовательность Command-down, V-down, V-up, Command-up - надёжнее,
        // чем одиночный V с флагом Command (часть приложений требует реального модификатора).
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55 // Command
        let vKey: CGKeyCode = 9    // 'v'
        func post(_ vk: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: keyDown) else { return }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cgSessionEventTap)
        }
        post(cmdKey, keyDown: true, flags: .maskCommand)
        post(vKey, keyDown: true, flags: .maskCommand)
        post(vKey, keyDown: false, flags: .maskCommand)
        post(cmdKey, keyDown: false, flags: [])

        // Возвращаем ПОЛНЫЙ прежний буфер (картинки/файлы/rich/несколько items), но ТОЛЬКО если
        // его никто не изменил после нас (changeCount тот же). Иначе - юзер/приложение успели
        // скопировать новое за эти 0.3с, и восстановление затёрло бы их свежий буфер.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let pb = NSPasteboard.general   // перефетч: не несём не-Sendable NSPasteboard через границу
            guard pb.changeCount == ourChangeCount else { return }
            pb.clearContents()
            restore(saved, into: pb)
        }
    }

    /// Снимок буфера в Sendable-форме (на каждый элемент: тип -> данные). Сохраняет картинки/файлы/
    /// rich/несколько элементов, а не только plain-строку. Sendable - безопасно нести в async-замыкание.
    private static func snapshot(_ pb: NSPasteboard) -> [[String: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type.rawValue] = data }
            }
            return dict
        }
    }

    private static func restore(_ items: [[String: Data]], into pb: NSPasteboard) {
        let objects: [NSPasteboardItem] = items.compactMap { dict in
            guard !dict.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (raw, data) in dict { item.setData(data, forType: NSPasteboard.PasteboardType(raw)) }
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
}
