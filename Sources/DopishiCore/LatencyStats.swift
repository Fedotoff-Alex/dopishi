import Foundation

/// Чистые вычисления перцентилей латентности.
/// Вынесено из актора SuggestionEventStore в Core - чтобы тестировать без in-memory GRDB.
public enum LatencyStats {
    /// p50/p95 по массиву значений латентности (мс). Сортирует копию (не мутирует вход).
    /// Пустой вход -> (0, 0). Индекс p95 ограничен последним элементом.
    public static func percentiles(_ values: [Int]) -> (p50: Int, p95: Int) {
        guard !values.isEmpty else { return (0, 0) }
        let sorted = values.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95Index = min(Int(Double(sorted.count) * 0.95), sorted.count - 1)
        let p95 = sorted[p95Index]
        return (p50, p95)
    }
}
