import Foundation

/// Причина, по которой гейт-фильтры отбросили подсказку (для A/B-бенча).
public enum RejectionReason: String, Sendable, Codable {
    case none             // подсказка принята
    case empty            // модель ничего не выдала
    case notPresentable   // SuggestionGate: пусто/мусор/только пунктуация
    case lowConfidence    // ConfidenceGate: avgLogprob ниже порога
    case languageMismatch // LanguageGuard: ушла в чужой язык (RU->EN/UA)
    case repetition       // RepetitionGuard: повтор хвоста контекста
}

/// Полная трасса одного прогона бенча: метрики скорости + качество + сырьё под debug.
public struct BenchTrace: Sendable, Codable {
    public var model: String
    public var promptMode: String
    public var prefixLabel: String
    public var contextSize: Int

    // Скорость
    public var prefillMs: Double          // декод промпта (prefill) до первого токена
    public var firstTokenMs: Double?      // первый сырой токен от модели
    public var firstVisibleMs: Double?    // первая ВИДИМАЯ подсказка (прошла гейты, готова к показу)
    public var totalMs: Double            // полный цикл генерации
    public var tokensPerSec: Double
    public var avgLogprob: Double

    // Качество
    public var suggestion: String         // финальная подсказка (после нормализации/гейтов), "" если reject
    public var suggestionWordCount: Int
    public var rejection: RejectionReason

    // Сырьё (debug)
    public var rawPromptTail: String      // хвост промпта (последние ~120 симв)
    public var rawOutput: String          // сырой вывод модели до нормализации

    public init(model: String, promptMode: String, prefixLabel: String, contextSize: Int,
                prefillMs: Double, firstTokenMs: Double?, firstVisibleMs: Double?,
                totalMs: Double, tokensPerSec: Double, avgLogprob: Double,
                suggestion: String, suggestionWordCount: Int, rejection: RejectionReason,
                rawPromptTail: String, rawOutput: String) {
        self.model = model
        self.promptMode = promptMode
        self.prefixLabel = prefixLabel
        self.contextSize = contextSize
        self.prefillMs = prefillMs
        self.firstTokenMs = firstTokenMs
        self.firstVisibleMs = firstVisibleMs
        self.totalMs = totalMs
        self.tokensPerSec = tokensPerSec
        self.avgLogprob = avgLogprob
        self.suggestion = suggestion
        self.suggestionWordCount = suggestionWordCount
        self.rejection = rejection
        self.rawPromptTail = rawPromptTail
        self.rawOutput = rawOutput
    }
}
