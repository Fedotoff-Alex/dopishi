import Foundation

/// Исход подсказки для записи в журнал событий suggestion_event.
/// String-backed для хранения в SQLite как rawValue.
public enum SuggestionEventOutcome: String, Sendable, Equatable, CaseIterable {
    case shown
    case accepted
    case dismissed
    case typedThrough
    case modelEmpty
    case refused
}

/// Событие жизненного цикла подсказки - чистый value type без I/O и без сырого текста пользователя.
/// Содержит только метаданные: исход, латентность, приложение, модель, класс подсказки.
/// Поля с сырым текстом (prefixTail, precedingText, suggestionText) намеренно отсутствуют (DATA-01, PII).
public struct SuggestionEvent: Sendable, Equatable {
    /// Ключ треда памяти (bundleId:windowId), без сырого текста.
    public let threadKey: String
    /// Bundle ID приложения, в котором появилась подсказка.
    public let appBundleId: String?
    /// Исход подсказки - SuggestionEventOutcome.rawValue.
    public let outcome: String
    /// Причина отказа - SuggestionRefusal.rawValue или nil.
    public let refusalReason: String?
    /// Латентность от начала запроса до первого токена (мс).
    public let latencyFirstMs: Int?
    /// Латентность от начала запроса до конца стрима (мс).
    public let latencyTotalMs: Int?
    /// Имя файла модели (без пути).
    public let modelFile: String?
    /// Режим промпта (chat, instruct и др.).
    public let promptMode: String?
    /// Класс подсказки: "completion" для LLM-пути; nil = неизвестен (например, refused-гейты).
    /// "correction" / "emoji" зарезервированы для будущих фаз.
    public let kind: String?
    /// Время создания события.
    public let createdAt: Date

    public init(
        threadKey: String,
        appBundleId: String?,
        outcome: String,
        refusalReason: String?,
        latencyFirstMs: Int?,
        latencyTotalMs: Int?,
        modelFile: String?,
        promptMode: String?,
        kind: String? = nil,
        createdAt: Date
    ) {
        self.threadKey = threadKey
        self.appBundleId = appBundleId
        self.outcome = outcome
        self.refusalReason = refusalReason
        self.latencyFirstMs = latencyFirstMs
        self.latencyTotalMs = latencyTotalMs
        self.modelFile = modelFile
        self.promptMode = promptMode
        self.kind = kind
        self.createdAt = createdAt
    }
}
