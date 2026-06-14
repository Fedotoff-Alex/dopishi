import Foundation

/// Накопленная статистика подсказок одного приложения за окно (из suggestion_event).
public struct AppSuggestStats: Sendable, Equatable {
    /// Всего событий приложения за окно (включая refused/modelEmpty) - зрелость статистики.
    public let total: Int
    public let shown: Int
    public let accepted: Int
    /// Последняя активность (для decay).
    public let lastEventAt: Date?

    public init(total: Int, shown: Int, accepted: Int, lastEventAt: Date?) {
        self.total = total
        self.shown = shown
        self.accepted = accepted
        self.lastEventAt = lastEventAt
    }
}

/// Параметры подсказок, подстроенные под приложение (MEM-02).
public struct AdaptiveParams: Sendable, Equatable {
    /// Порог ConfidenceGate (минимальная средняя logprob).
    public let minConfidence: Double
    /// Максимум слов дополнения.
    public let maxWords: Int
    /// Доля АВТО-запросов, идущих в генерацию [showRateFloor...1.0]. Хоткея не касается.
    public let showRate: Double

    public init(minConfidence: Double, maxWords: Int, showRate: Double) {
        self.minConfidence = minConfidence
        self.maxWords = maxWords
        self.showRate = showRate
    }
}

/// Adaptive policy per-app (MEM-02): подстройка порога/длины/частоты по накопленной
/// статистике принятия. Чистые функции - вся логика тестируема без БД и часов.
public enum AdaptivePolicy {
    /// Cold-start: первые N событий приложения работаем на global defaults.
    public static let coldStartEvents = 30
    /// Decay: после стольких секунд простоя статистика устарела - сброс к global.
    public static let decaySeconds: TimeInterval = 7 * 86400
    /// Floor частоты показа: policy не имеет права замолчать совсем.
    public static let showRateFloor = 0.3
    /// Explore: каждый N-й запрос - разведка на global-параметрах (собирает данные
    /// для выхода из строгого режима).
    public static let exploreEvery = 7

    /// Адаптированные параметры приложения. Cold-start / decay / нет статистики -> global.
    public static func params(global: AdaptiveParams, stats: AppSuggestStats?,
                              now: Date = Date()) -> AdaptiveParams {
        guard let stats, stats.total >= coldStartEvents, stats.shown > 0 else { return global }
        if let last = stats.lastEventAt, now.timeIntervalSince(last) > decaySeconds { return global }
        let acceptance = Double(stats.accepted) / Double(stats.shown)
        if acceptance >= 0.25 {
            // Попадаем в стиль: мягче порог, длиннее дополнение, полный поток.
            return AdaptiveParams(minConfidence: global.minConfidence - 0.5,
                                  maxWords: min(12, global.maxWords + 2),
                                  showRate: 1.0)
        }
        if acceptance < 0.05 {
            // Почти не принимают: строже, короче, реже - но floor не даёт замолчать.
            return AdaptiveParams(minConfidence: global.minConfidence + 0.5,
                                  maxWords: max(2, global.maxWords - 2),
                                  showRate: showRateFloor)
        }
        if acceptance < 0.12 {
            return AdaptiveParams(minConfidence: global.minConfidence + 0.25,
                                  maxWords: max(2, global.maxWords - 1),
                                  showRate: 0.6)
        }
        return global   // средняя зона - сигнала на подстройку нет
    }

    /// Параметры конкретного запроса: explore-такт идёт на global (разведка), остальные -
    /// на адаптированных.
    public static func paramsForRequest(index: Int, adaptive: AdaptiveParams,
                                        global: AdaptiveParams) -> AdaptiveParams {
        index % exploreEvery == 0 ? global : adaptive
    }

    /// Пускать ли АВТО-запрос с этим индексом в генерацию. Детерминированное
    /// Bresenham-прореживание (floor((i+1)r) > floor(ir) - true ровно в r-доле тактов);
    /// explore-такты проходят всегда. Хоткей-запросы сюда не ходят (явная просьба).
    public static func admits(requestIndex: Int, showRate: Double) -> Bool {
        if requestIndex % exploreEvery == 0 { return true }
        let rate = min(1.0, max(showRateFloor, showRate))
        if rate >= 1.0 { return true }
        let i = Double(requestIndex)
        return Int(((i + 1) * rate).rounded(.down)) > Int((i * rate).rounded(.down))
    }
}
