import AppKit
import ApplicationServices
import DopishiCore

struct AXReadResult: Equatable {
    var text: String?        // текст до каретки (nil, если недоступен)
    var caretRect: CGRect?   // экранный rect каретки (nil, если недоступен)
    var appBundleId: String?
    var isSecure: Bool
    var caretFontName: String? = nil
    var caretFontSize: CGFloat? = nil
    var selectedText: String? = nil
    var focusedWindowId: CGWindowID? = nil      // CGWindowID окна с фокусом (для OCR-захвата)
    var focusedWindowFrame: CGRect? = nil       // экранная рамка окна (top-left) для конверсии каретки
}

/// Приватный (недокументированный, но стабильный годами) символ: CGWindowID для AX-окна.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AccessibilityReader {
    static func read(enableEnhancedUI: Bool = false) -> AXReadResult {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appBundleId = frontApp?.bundleIdentifier
        if enableEnhancedUI, let pid = frontApp?.processIdentifier {
            enableManualAccessibility(pid: pid)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedErr == .success, let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return AXReadResult(text: nil, caretRect: nil, appBundleId: appBundleId, isSecure: false)
        }
        let element = focusedRef as! AXUIElement

        // Secure-поле -> ничего не читаем.
        if copyStringAttr(element, kAXSubroleAttribute as CFString) == (kAXSecureTextFieldSubrole as String) {
            return AXReadResult(text: nil, caretRect: nil, appBundleId: appBundleId, isSecure: true)
        }

        let fullText = copyStringAttr(element, kAXValueAttribute as CFString)
        let caretLocation = copyCaretLocation(element)

        var precedingText: String? = nil
        if let fullText {
            if let loc = caretLocation {
                precedingText = TextPrefix.byUTF16Offset(fullText, offset: loc)
            } else {
                precedingText = fullText
            }
        }

        let caretRect = resolveCaretRect(element, location: caretLocation)
        let font = caretLocation.flatMap { copyCaretFont(element, location: $0) }
        let (winId, winFrame) = focusedWindowInfo(element, appPid: frontApp?.processIdentifier)

        return AXReadResult(text: precedingText, caretRect: caretRect, appBundleId: appBundleId, isSecure: false, caretFontName: font?.fontName, caretFontSize: font?.pointSize, selectedText: copySelectedText(element), focusedWindowId: winId, focusedWindowFrame: winFrame)
    }

    /// CGWindowID + экранная рамка окна сфокусированного элемента (для OCR-захвата).
    private static func focusedWindowInfo(_ element: AXUIElement, appPid: pid_t?) -> (CGWindowID?, CGRect?) {
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else {
            // AX-окна нет (часто Electron/Chromium - виртуальное дерево) -> CG-фолбэк по pid.
            return (frontWindowID(forPid: appPid), nil)
        }
        let window = winRef as! AXUIElement
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(window, &wid) == .success, wid != 0 {
            return (wid, windowAXFrame(window))
        }
        // AX-окно есть, но приватный символ не дал windowID -> CG-фолбэк, frame из AX.
        return (frontWindowID(forPid: appPid), windowAXFrame(window))
    }

    /// Фронтовое onscreen-окно процесса (слой 0) через CGWindowListCopyWindowInfo - фолбэк, когда
    /// AX не отдаёт CGWindowID (Electron). Это ровно окно, которое захватит ScreenCaptureKit.
    private static func frontWindowID(forPid pid: pid_t?) -> CGWindowID? {
        guard let pid else { return nil }
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infos {   // z-порядок спереди назад - берём первое подходящее окно
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            return num
        }
        return nil
    }

    private static func windowAXFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    // MARK: - helpers

    /// pid приложений, которым уже включили AX-bridge / которые его не поддерживают.
    /// read() вызывается только с главного потока (ContextProbe.recompute @MainActor) - гонок нет.
    private nonisolated(unsafe) static var manualAXPids = Set<pid_t>()
    private nonisolated(unsafe) static var unsupportedAXPids = Set<pid_t>()

    /// Будим ленивое accessibility-дерево Electron/Chromium (тогда отдаёт текст/каретку).
    /// Способ Cotabby: AXManualAccessibility на app-элементе (по pid) - без побочки на оконные
    /// менеджеры (в отличие от AXEnhancedUserInterface). При отсутствии атрибута - запасной Enhanced.
    private static func enableManualAccessibility(pid: pid_t) {
        guard !manualAXPids.contains(pid), !unsupportedAXPids.contains(pid) else { return }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 0.05)
        let err = AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if err == .success {
            manualAXPids.insert(pid)
        } else {
            // Старые Electron не объявляют AXManualAccessibility - пробуем Enhanced как запасной.
            AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            unsupportedAXPids.insert(pid)
        }
    }

    private static func copyStringAttr(_ element: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func copyCaretLocation(_ element: AXUIElement) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    /// Выделенный текст (kAXSelectedText). nil или пусто - выделения нет.
    /// Читаем атрибут напрямую: проверка диапазона раньше падала в части полей.
    private static func copySelectedText(_ element: AXUIElement) -> String? {
        guard let s = copyStringAttr(element, kAXSelectedTextAttribute as CFString), !s.isEmpty else { return nil }
        return s
    }

    private static func copyCaretFont(_ element: AXUIElement, location: Int) -> NSFont? {
        // Каретка часто стоит в конце строки - тогда диапазон [location, 1] выходит за текст
        // и AX вернёт пусто. Читаем шрифт символа ПЕРЕД кареткой (последний набранный).
        let fontLocation = location > 0 ? location - 1 : location
        var range = CFRange(location: fontLocation, length: 1)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXAttributedStringForRangeParameterizedAttribute as CFString, axRange, &ref) == .success,
              let attr = ref as? NSAttributedString, attr.length > 0 else { return nil }
        let attrs = attr.attributes(at: 0, effectiveRange: nil)
        // Шрифт приходит либо готовым NSFont (.font), либо AX-словарём "AXFont"
        // (AXFontName/AXFontSize). Нативные NSTextView (TextEdit/Mail/Notes) дают именно словарь,
        // а не .font - поэтому раньше шрифт не подтягивался и кегль уезжал в fallback. Рецепт Cotabby.
        if let f = attrs[.font] as? NSFont {
            return f
        }
        if let info = attrs[NSAttributedString.Key("AXFont")] as? [String: Any],
           let sizeNum = info["AXFontSize"] as? NSNumber, sizeNum.doubleValue > 0 {
            let size = CGFloat(sizeNum.doubleValue)
            if let name = info["AXFontName"] as? String, let f = NSFont(name: name, size: size) {
                return f
            }
            return NSFont.systemFont(ofSize: size)
        }
        return nil
    }

    private static func copyCaretRect(_ element: AXUIElement, location: Int) -> CGRect? {
        var range = CFRange(location: location, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &ref)
        guard err == .success, let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Позиция каретки через приватный AXTextMarker (работает в Chromium/Electron,
    /// где kAXBoundsForRangeParameterized битый). Рецепт Cotabby.
    private static func textMarkerCaretRect(_ element: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markerRange else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        let axValue = boundsValue as! AXValue
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Branch 2 (Cotabby): позиция каретки по ПРАВОМУ краю символа перед ней.
    /// Помогает в полях, которые не дают bounds нулевого диапазона, но дают bounds символа.
    private static func prevCharCaretRect(_ element: AXUIElement, location: Int) -> CGRect? {
        guard location > 0 else { return nil }
        var range = CFRange(location: location - 1, length: 1)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
        // Каретка - у правого края предыдущего символа. Ширину коллапсируем до 0: ghost берёт
        // maxX, и при ширине 0 это точка вставки (как у zero-range), без лишнего сдвига вправо.
        return CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
    }

    /// Лучшая доступная позиция каретки: сперва стандартный bounds (нативные поля),
    /// при отсутствии/битом результате - AXTextMarker (Electron/Chromium),
    /// третий вариант - Branch 2 по правому краю символа перед кареткой.
    private static func resolveCaretRect(_ element: AXUIElement, location: Int?) -> CGRect? {
        // prevChar (rect ПОСЛЕДНЕГО глифа, правый край) - первым: NSTextView (TextEdit/Telegram и
        // др. нативные поля) отдаёт bounds НУЛЕВОГО диапазона на высоту строки ВЫШЕ реального глифа
        // (замерено: zeroRange Y=406, prevChar Y=420, ровно на строку, даже выше верха поля). X у
        // prevChar тот же. На Electron prevChar/zero-range битые (isPlausibleCaret их отсечёт) -
        // там остаётся textMarker, поведение не меняется.
        if let loc = location, loc > 0, let rect = prevCharCaretRect(element, location: loc), isPlausibleCaret(rect) {
            return rect
        }
        if let loc = location, let rect = copyCaretRect(element, location: loc), isPlausibleCaret(rect) {
            return rect
        }
        if let rect = textMarkerCaretRect(element), isPlausibleCaret(rect) {
            return rect
        }
        return nil
    }

    /// Отсекаем заведомо битый rect: Electron при сломанном kAXBoundsForRange отдаёт
    /// прямоугольник во весь экран (0, высота_экрана) - нереальные размеры каретки.
    private static func isPlausibleCaret(_ rect: CGRect) -> Bool {
        rect.height > 0 && rect.height < 200 && rect.width < 2000
    }
}
