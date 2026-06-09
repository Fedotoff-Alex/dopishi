import Foundation

/// Накопитель прод-телеметрии: сколько подсказок показано и сколько скрыто каким гейтом,
/// с разбивкой по приложению. Нужен, чтобы крутить пороги (minConfidence/LanguageGuard/
/// app-профили) по реальному набору, а не на глаз. Значимое - именно ПРИЧИНА скрытия.
/// Обновления функциональные (возвращают новое значение) - без мутаций общего состояния.
public struct RejectionTally: Sendable, Equatable {
    public private(set) var shown: Int
    public private(set) var byReason: [RejectionReason: Int]
    public private(set) var byApp: [String: [RejectionReason: Int]]

    public init(shown: Int = 0,
                byReason: [RejectionReason: Int] = [:],
                byApp: [String: [RejectionReason: Int]] = [:]) {
        self.shown = shown
        self.byReason = byReason
        self.byApp = byApp
    }

    /// Подсказка показана пользователю.
    public func recordingShown(app: String?) -> RejectionTally {
        RejectionTally(shown: shown + 1, byReason: byReason, byApp: byApp)
    }

    /// Подсказка скрыта гейтом - фиксируем причину (глобально и по приложению).
    public func recording(reason: RejectionReason, app: String?) -> RejectionTally {
        var reasons = byReason
        reasons[reason, default: 0] += 1
        var apps = byApp
        let key = app ?? "-"
        var appReasons = apps[key] ?? [:]
        appReasons[reason, default: 0] += 1
        apps[key] = appReasons
        return RejectionTally(shown: shown, byReason: reasons, byApp: apps)
    }

    public var totalRejected: Int { byReason.values.reduce(0, +) }

    /// Краткая сводка для лога/HUD: показано N, скрыто по причинам.
    public func summary() -> String {
        let reasons = byReason
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: " ")
        return "shown=\(shown) rejected=\(totalRejected) [\(reasons)]"
    }
}
