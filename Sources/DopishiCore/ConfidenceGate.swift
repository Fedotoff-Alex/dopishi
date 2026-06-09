import Foundation

public enum ConfidenceGate {
    /// Показывать подсказку только если средняя логвероятность сгенерированных токенов
    /// не ниже порога. Низкая средняя logprob = модель не уверена/гадает (типичный мусор
    /// на кривом вводе) -> не показываем. Так делает Cotypist (minimumConfidence).
    public static func isConfident(averageLogprob: Double, minimum: Double) -> Bool {
        averageLogprob >= minimum
    }
}
