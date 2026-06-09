import Foundation

/// Распознанный OCR-контекст окна (один готовый снимок). Живёт только в RAM, не персистится.
public struct OCRContext: Sendable, Equatable {
    public let windowText: String   // уже отобранный/обрезанный текст рядом с кареткой
    public let capturedAt: Date     // для TTL/диагностики
    public let windowId: UInt32     // CGWindowID - ключ кэша

    public init(windowText: String, capturedAt: Date, windowId: UInt32) {
        self.windowText = windowText
        self.capturedAt = capturedAt
        self.windowId = windowId
    }
}

/// Набор контекстных каналов для промпта. fieldTail обязателен (хвост поля, как сейчас),
/// ocr опционален (последний готовый снимок окна; nil когда фича off/secure/нет прав).
public struct ContextBundle: Sendable, Equatable {
    public let fieldTail: String
    public let ocr: OCRContext?
    /// Релевантный текст буфера обмена (опц. канал). nil когда фича off/secure/excluded/нерелевантно.
    /// Уже прошёл relevance-фильтр + дистилляцию + санитайз; кладётся как есть в промпт.
    public let clipboard: String?
    /// Снимок локальной памяти потока (опц. канал «Память:»). nil когда фича off/secure/excluded/пусто.
    public let memory: String?

    public init(fieldTail: String, ocr: OCRContext? = nil, clipboard: String? = nil, memory: String? = nil) {
        self.fieldTail = fieldTail
        self.ocr = ocr
        self.clipboard = clipboard
        self.memory = memory
    }
}
