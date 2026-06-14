import Foundation
import CoreGraphics

public struct EditingContext: Sendable, Equatable {
    public let precedingText: String
    public let caretScreenRect: CGRect?
    public let appBundleId: String?
    public let capability: CapabilityTier
    public let isSecure: Bool
    public let caretFontName: String?
    public let caretFontSize: CGFloat?
    public let selectedText: String?
    /// Текст СРАЗУ ПОСЛЕ каретки (хвост окна чтения, до ~200 UTF-16 единиц). Пустой, когда
    /// каретка в конце текста. Нужен гейту «каретка в середине текста»: ghost рисуется
    /// вправо от каретки и лёг бы ПОВЕРХ этого текста.
    public let followingText: String
    /// Текст, набранный с клавиатуры с момента фокуса/сброса (KeystrokeBuffer). Это
    /// НЕМЕДЛЕННАЯ правда о наборе (CGEventTap не лагает), в отличие от precedingText из AX,
    /// который в Electron отстаёт. Пусто, если буфера нет (вставка, после клика).
    public let typedSinceFocus: String
    /// Последний готовый OCR-снимок окна (опц. канал контекста). nil когда фича off/secure/
    /// нет прав/excluded. Никогда не ждётся генерацией - кладётся как есть.
    public let ocr: OCRContext?
    /// Релевантный текст буфера обмена (опц. канал). nil когда фича off/secure/excluded/нерелевантно.
    public let clipboard: String?
    /// Снимок локальной памяти потока (опц. канал «Память:»). nil когда фича off/secure/excluded/пусто.
    public let memory: String?

    public init(precedingText: String, caretScreenRect: CGRect?, appBundleId: String?, capability: CapabilityTier, isSecure: Bool, caretFontName: String? = nil, caretFontSize: CGFloat? = nil, selectedText: String? = nil, typedSinceFocus: String = "", ocr: OCRContext? = nil, clipboard: String? = nil, memory: String? = nil, followingText: String = "") {
        self.followingText = followingText
        self.precedingText = precedingText
        self.caretScreenRect = caretScreenRect
        self.appBundleId = appBundleId
        self.capability = capability
        self.isSecure = isSecure
        self.caretFontName = caretFontName
        self.caretFontSize = caretFontSize
        self.selectedText = selectedText
        self.typedSinceFocus = typedSinceFocus
        self.ocr = ocr
        self.clipboard = clipboard
        self.memory = memory
    }

    /// Копия с другим precedingText (для tail-from-memory: после Tab latest = пост-вставка).
    public func withPrecedingText(_ text: String) -> EditingContext {
        EditingContext(precedingText: text, caretScreenRect: caretScreenRect, appBundleId: appBundleId,
                       capability: capability, isSecure: isSecure, caretFontName: caretFontName,
                       caretFontSize: caretFontSize, selectedText: selectedText,
                       typedSinceFocus: typedSinceFocus, ocr: ocr, clipboard: clipboard, memory: memory,
                       followingText: followingText)
    }
}

public enum EditingContextBuilder {
    /// Собирает контекст из данных Accessibility (основное) и фолбэк-буфера.
    /// - axText: текст до каретки из AX (nil, если AX не отдал).
    /// - fallbackText: текст из KeystrokeBuffer.
    /// - caretRect: экранный прямоугольник каретки из AX (nil, если недоступен).
    public static func build(
        axText: String?,
        fallbackText: String,
        caretRect: CGRect?,
        appBundleId: String?,
        isSecure: Bool,
        axFontName: String? = nil,
        axFontSize: CGFloat? = nil,
        selectedText: String? = nil,
        keystrokeText: String = "",
        ocr: OCRContext? = nil,
        clipboard: String? = nil,
        memory: String? = nil,
        axFollowingText: String = ""
    ) -> EditingContext {
        if isSecure {
            // secure-поле: ни текста, ни OCR (не захватываем секреты).
            return EditingContext(precedingText: "", caretScreenRect: nil,
                                  appBundleId: appBundleId, capability: .none, isSecure: true)
        }
        let text = axText ?? fallbackText
        let tier = Capability.classify(hasText: !text.isEmpty, hasCaretRect: caretRect != nil)
        return EditingContext(
            precedingText: text,
            caretScreenRect: tier == .full ? caretRect : nil,
            appBundleId: appBundleId,
            capability: tier,
            isSecure: false,
            caretFontName: axFontName,
            caretFontSize: axFontSize,
            selectedText: selectedText,
            typedSinceFocus: keystrokeText,
            ocr: ocr,
            clipboard: clipboard,
            memory: memory,
            followingText: axFollowingText
        )
    }
}
