import Foundation
import DopishiCore
import LocalLLMClient
import LocalLLMClientLlama

/// Конфиг движка: sampling + режим промпта + лимиты вывода. Дефолт `.production` повторяет
/// исторические захардкоженные значения (поведение приложения не меняется). Бенч подаёт
/// свои конфиги для A/B по моделям/режимам/семплингу.
public struct EngineConfig: Sendable {
    public var temperature: Double
    public var topK: Int
    public var topP: Double
    public var penaltyRepeat: Double
    public var penaltyLastN: Int
    public var contextSize: Int
    public var extraEOSTokens: [String]
    public var promptMode: PromptBuilder.Mode
    public var maxWords: Int
    public var maxChunks: Int
    public var maxCharacters: Int
    public var hardTimeBudget: TimeInterval
    public var minConfidence: Double

    public init(temperature: Double, topK: Int, topP: Double, penaltyRepeat: Double,
                penaltyLastN: Int, contextSize: Int, extraEOSTokens: [String],
                promptMode: PromptBuilder.Mode, maxWords: Int, maxChunks: Int,
                maxCharacters: Int, hardTimeBudget: TimeInterval, minConfidence: Double) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.penaltyRepeat = penaltyRepeat
        self.penaltyLastN = penaltyLastN
        self.contextSize = contextSize
        self.extraEOSTokens = extraEOSTokens
        self.promptMode = promptMode
        self.maxWords = maxWords
        self.maxChunks = maxChunks
        self.maxCharacters = maxCharacters
        self.hardTimeBudget = hardTimeBudget
        self.minConfidence = minConfidence
    }

    /// Продакшн-дефолт (= прежние захардкоженные значения). promptMode уважает
    /// DOPISHI_PROMPT_MODE для A/B без пересборки.
    public static let production: EngineConfig = {
        var c = EngineConfig(
            temperature: 0.6, topK: 64, topP: 0.95, penaltyRepeat: 1.0, penaltyLastN: 32,
            contextSize: 2048, extraEOSTokens: ["\n"], promptMode: .fewShot,
            maxWords: 6, maxChunks: 24, maxCharacters: 96, hardTimeBudget: 0.55, minConfidence: -3.0
        )
        switch ProcessInfo.processInfo.environment["DOPISHI_PROMPT_MODE"]?.lowercased() {
        case "plain": c.promptMode = .plainTrimmed
        case "plainraw": c.promptMode = .plainRaw
        case "minimal": c.promptMode = .minimalInline
        case "gemma", "gemmaautocomplete": c.promptMode = .gemmaChat
        default: break
        }
        return c
    }()
}

public actor SuggestionEngine {
    private var client: LlamaClient?
    /// In-flight загрузка модели: warm-up и первая генерация не должны грузить модель дважды
    /// (две параллельные инициализации llama/Metal-контекста = риск гонки).
    private var loadTask: Task<LlamaClient, Error>?
    /// Последняя генерация: новая ждёт её полной остановки. llama-decode НЕ параллелится -
    /// два одновременных decode на одном контексте рвут Metal-ресурсы (SIGSEGV).
    private var lastGeneration: Task<Void, Never>?
    private let modelURL: URL
    private let config: EngineConfig
    /// Прод-телеметрия скрытий подсказок (почему гейт скрыл, по приложению).
    private var tally = RejectionTally()
    /// Runtime-оверрайды из настроек (меняются БЕЗ пересоздания движка/перезагрузки модели):
    /// длина дополнения (maxWords) и пользовательские указания в голову промпта.
    private var runtimeMaxWords: Int?
    private var runtimeInstructions: String = ""

    /// Применить настройки длины/указаний на лету (вызывается из applySettings контроллера).
    public func applyRuntime(maxWords: Int, instructions: String) {
        runtimeMaxWords = max(1, maxWords)
        runtimeInstructions = instructions
    }

    public init(fileName: String = ModelCatalog.defaultFileName, config: EngineConfig? = nil) {
        self.modelURL = ModelLocator.url(forFile: fileName)
        // Без явного конфига - продакшн-дефолты + per-model стоп-токены (Gemma-3 <end_of_turn>,
        // Qwen <|im_end|> и т.п.). Бенч подаёт свой конфиг для A/B и этим путём не идёт.
        if let config {
            self.config = config
        } else {
            var c = EngineConfig.production
            c.extraEOSTokens = ModelStopTokens.tokens(for: fileName)
            self.config = c
        }
    }

    private func loadedClient() async throws -> LlamaClient {
        if let client { return client }
        // Уже грузится (warm-up на старте) - ждём тот же Task, не плодим второй контекст.
        if let loadTask { return try await loadTask.value }
        let url = modelURL
        let cfg = config
        let task = Task { () async throws -> LlamaClient in
            var p = LlamaClient.Parameter.default
            p.context = cfg.contextSize
            p.temperature = Float(cfg.temperature)
            p.topK = cfg.topK
            p.topP = Float(cfg.topP)
            p.penaltyLastN = cfg.penaltyLastN
            p.penaltyRepeat = Float(cfg.penaltyRepeat)
            p.options.extraEOSTokens = Set(cfg.extraEOSTokens)
            return try await LocalLLMClient.llama(url: url, parameter: p)
        }
        loadTask = task
        do {
            let c = try await task.value
            client = c
            loadTask = nil
            return c
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Прогрев: грузит модель (mmap весов + аллокация контекста) заранее, чтобы первая реальная
    /// подсказка не платила холодный путь. Зовётся в фоне на старте и при смене модели.
    public func warmUp() async {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        _ = try? await loadedClient()
    }

    /// Обёртка для совместимости: стрим только по хвосту поля (без OCR-канала).
    public func stream(prefix: String, appId: String? = nil) -> AsyncThrowingStream<String, Error> {
        stream(bundle: ContextBundle(fieldTail: prefix), appId: appId)
    }

    /// Стрим короткой подсказки-продолжения по набору каналов контекста (хвост поля + опц. OCR).
    /// Применяет PromptBuilder/ContextBuilder + CompletionStop; уважает отмену Task.
    /// Гейты работают строго по bundle.fieldTail (OCR в echo/repetition/language не попадает).
    public func stream(bundle: ContextBundle, appId: String? = nil) -> AsyncThrowingStream<String, Error> {
        let url = modelURL
        let cfg = config
        let app = appId
        let prefix = bundle.fieldTail
        let instructions = runtimeInstructions
        let maxWords = runtimeMaxWords ?? cfg.maxWords
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        // Сериализация генераций: llama-context НЕ потокобезопасен. Если новая подсказка
        // стартует, пока прежняя ещё считает (быстрый набор / поллинг Electron), два параллельных
        // decode рвут Metal-ресурсы -> SIGSEGV. Новая ждёт .value предыдущей: та уже отменена
        // вызывающим (task.cancel через onTermination) и завершится за пару чанков.
        let previous = lastGeneration
        let task = Task {
            await previous?.value
            do {
                if Task.isCancelled { continuation.finish(); return }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continuation.finish(); return
                }
                let client = try await self.loadedClient()
                // Есть OCR или буфер - собираем few-shot с секциями "Окно:"/"Буфер:" (KV-голова
                // цела); иначе обычный путь (нулевая регрессия).
                let prompt = (bundle.ocr == nil && bundle.clipboard == nil && bundle.memory == nil)
                    ? PromptBuilder.build(mode: cfg.promptMode, from: prefix,
                                          modelFileName: url.lastPathComponent, instructions: instructions)
                    : ContextBuilder.build(bundle, instructions: instructions)
                let decodeStartedAt = Date()
                let generator = try client.textStream(from: .plain(prompt))
                let decodeMs = Date().timeIntervalSince(decodeStartedAt) * 1000
                let startedAt = Date()
                var acc = ""
                var finalText = ""
                var chunkCount = 0
                var lastYielded: String?
                var firstYieldMs: Double?
                var didYield = false
                for try await chunk in generator {
                    try Task.checkCancellation()
                    chunkCount += 1
                    acc += chunk
                    let r = CompletionStop.evaluate(acc, maxWords: maxWords)
                    finalText = acc
                    if r.shouldStop {
                        finalText = r.trimmed
                        break
                    }

                    let elapsed = Date().timeIntervalSince(startedAt)
                    if SuggestionPreview.isStable(r.trimmed),
                       let preview = Self.presentableSuggestion(
                           raw: r.trimmed,
                           prefix: prefix,
                           averageLogprob: client.averageLogprob,
                           minConfidence: cfg.minConfidence
                       ),
                       preview != lastYielded {
                        continuation.yield(preview)
                        lastYielded = preview
                        didYield = true
                        if firstYieldMs == nil {
                            firstYieldMs = Date().timeIntervalSince(startedAt) * 1000
                        }
                    }

                    if chunkCount >= cfg.maxChunks ||
                       acc.count >= cfg.maxCharacters ||
                       elapsed >= cfg.hardTimeBudget {
                        finalText = r.trimmed
                        break
                    }
                }
                let (finalSug, finalReason) = Self.presentableSuggestionDebug(
                    raw: finalText, prefix: prefix,
                    averageLogprob: client.averageLogprob, minConfidence: cfg.minConfidence)
                if let final = finalSug, final != lastYielded {
                    continuation.yield(final)
                    didYield = true
                    if firstYieldMs == nil {
                        firstYieldMs = Date().timeIntervalSince(startedAt) * 1000
                    }
                }
                // Прод-телеметрия: показано или скрыто (и какой именно гейт скрыл).
                // Task здесь actor-isolated (создан в методе актора) - вызов без cross-actor await.
                self.recordOutcome(shown: didYield, reason: finalReason, appId: app)
                Self.logTimingsIfNeeded(
                    decodeMs: decodeMs,
                    firstYieldMs: firstYieldMs,
                    totalMs: Date().timeIntervalSince(decodeStartedAt) * 1000,
                    chunks: chunkCount,
                    promptCharacters: prompt.count,
                    outputCharacters: finalText.count,
                    averageLogprob: client.averageLogprob
                )
                continuation.finish()
            } catch is CancellationError {
                // Отмена (новое нажатие/смена контекста) - НЕ исход: телеметрию намеренно
                // не пишем. tally считает только генерации, дошедшие до конца (показ/скрытие
                // гейтом), а не прерванные на полпути. Это корректно: "из завершённых
                // генераций какая доля скрыта и каким гейтом".
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        lastGeneration = task
        return stream
    }

    /// Один прогон бенча: полная трасса (скорость + качество + причина reject + сырьё).
    /// Зеркалит логику stream(), но записывает метрики вместо стрима в overlay.
    public func benchRun(prefix: String, label: String) async throws -> BenchTrace {
        let client = try await loadedClient()
        let prompt = PromptBuilder.build(mode: config.promptMode, from: prefix,
                                         modelFileName: modelURL.lastPathComponent)
        let decodeStartedAt = Date()
        let generator = try client.textStream(from: .plain(prompt))
        let prefillMs = Date().timeIntervalSince(decodeStartedAt) * 1000
        let startedAt = Date()
        var acc = ""
        var finalText = ""
        var chunkCount = 0
        var firstTokenMs: Double?
        var firstVisibleMs: Double?
        for try await chunk in generator {
            chunkCount += 1
            if firstTokenMs == nil { firstTokenMs = Date().timeIntervalSince(startedAt) * 1000 }
            acc += chunk
            let r = CompletionStop.evaluate(acc, maxWords: config.maxWords)
            finalText = acc
            if r.shouldStop { finalText = r.trimmed; break }
            let elapsed = Date().timeIntervalSince(startedAt)
            if firstVisibleMs == nil, SuggestionPreview.isStable(r.trimmed),
               Self.presentableSuggestionDebug(raw: r.trimmed, prefix: prefix,
                                               averageLogprob: client.averageLogprob,
                                               minConfidence: config.minConfidence).0 != nil {
                firstVisibleMs = Date().timeIntervalSince(startedAt) * 1000
            }
            if chunkCount >= config.maxChunks || acc.count >= config.maxCharacters
               || elapsed >= config.hardTimeBudget {
                finalText = r.trimmed; break
            }
        }
        let genSec = max(0.001, Date().timeIntervalSince(startedAt))
        let (finalSug, reason) = Self.presentableSuggestionDebug(
            raw: finalText, prefix: prefix, averageLogprob: client.averageLogprob,
            minConfidence: config.minConfidence)
        let suggestion = finalSug ?? ""
        return BenchTrace(
            model: modelURL.lastPathComponent,
            promptMode: config.promptMode.rawValue,
            prefixLabel: label,
            contextSize: config.contextSize,
            prefillMs: prefillMs,
            firstTokenMs: firstTokenMs,
            firstVisibleMs: firstVisibleMs,
            totalMs: Date().timeIntervalSince(decodeStartedAt) * 1000,
            tokensPerSec: Double(chunkCount) / genSec,
            avgLogprob: client.averageLogprob,
            suggestion: suggestion,
            suggestionWordCount: suggestion.split(separator: " ").count,
            rejection: finalSug != nil ? .none : reason,
            rawPromptTail: String(prompt.suffix(120)),
            rawOutput: finalText
        )
    }

    /// Зафиксировать исход прод-генерации: показано или скрыто (с причиной), по приложению.
    /// Под env DOPISHI_REJECTIONS=1 пишет причину скрытия в лог.
    private func recordOutcome(shown: Bool, reason: RejectionReason, appId: String?) {
        if shown {
            tally = tally.recordingShown(app: appId)
        } else {
            tally = tally.recording(reason: reason, app: appId)
            if ProcessInfo.processInfo.environment["DOPISHI_REJECTIONS"] == "1" {
                NSLog("DopishiLLM rejection reason=%@ app=%@ | %@",
                      reason.rawValue, appId ?? "-", tally.summary())
            }
        }
    }

    /// Текущая сводка телеметрии скрытий (для HUD/диагностики).
    public func rejectionTally() -> RejectionTally { tally }

    private static func presentableSuggestion(raw: String, prefix: String,
                                              averageLogprob: Double, minConfidence: Double) -> String? {
        presentableSuggestionDebug(raw: raw, prefix: prefix,
                                   averageLogprob: averageLogprob, minConfidence: minConfidence).0
    }

    /// Гейты по очереди с возвратом причины первого отказа (для бенча).
    static func presentableSuggestionDebug(raw: String, prefix: String, averageLogprob: Double,
                                           minConfidence: Double) -> (String?, RejectionReason) {
        let cleaned = SuggestionNormalizer.normalize(raw)
        let unechoed = EchoPrefixGuard.strip(cleaned, context: prefix)
        if unechoed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (nil, .empty) }
        if !SuggestionGate.isPresentable(unechoed) { return (nil, .notPresentable) }
        if !ConfidenceGate.isConfident(averageLogprob: averageLogprob, minimum: minConfidence) {
            return (nil, .lowConfidence)
        }
        if !LanguageGuard.allows(suggestion: unechoed, givenContext: prefix) {
            return (nil, .languageMismatch)
        }
        guard let deduped = RepetitionGuard.filter(suggestion: unechoed, context: prefix) else {
            return (nil, .repetition)
        }
        return (deduped, .none)
    }

    private static func logTimingsIfNeeded(decodeMs: Double, firstYieldMs: Double?, totalMs: Double,
                                           chunks: Int, promptCharacters: Int, outputCharacters: Int,
                                           averageLogprob: Double) {
        guard ProcessInfo.processInfo.environment["DOPISHI_LLM_TIMINGS"] == "1" else { return }
        let first = firstYieldMs.map { String(format: "%.0f", $0) } ?? "-"
        NSLog("DopishiLLM timings decode=%.0fms firstYield=%@ms total=%.0fms chunks=%d promptChars=%d outputChars=%d avgLogprob=%.2f",
              decodeMs, first, totalMs, chunks, promptCharacters, outputCharacters, averageLogprob)
    }
}
