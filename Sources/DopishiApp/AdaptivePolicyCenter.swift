import Foundation
import DopishiCore
import DopishiMemory

/// Кэш per-app статистики для adaptive policy (MEM-02). Параметры отдаёт СИНХРОННО -
/// hot-path подсказки никогда не ждёт БД: кэш освежается фоном, не чаще раза в 60с
/// на приложение. eventStore == nil (телеметрия выключена) -> всегда global, политика
/// молча деградирует.
@MainActor
final class AdaptivePolicyCenter {
    var eventStore: SuggestionEventStore? {
        didSet { if eventStore == nil { invalidate() } }
    }
    private var cache: [String: AppSuggestStats] = [:]
    private var refreshedAt: [String: Date] = [:]

    /// Adaptive-параметры приложения по кэшу статистики (+ фоновое освежение кэша).
    func params(for appId: String?, global: AdaptiveParams) -> AdaptiveParams {
        guard let appId, let store = eventStore else { return global }
        refreshIfStale(appId, store: store)
        return AdaptivePolicy.params(global: global, stats: cache[appId])
    }

    private func refreshIfStale(_ appId: String, store: SuggestionEventStore) {
        let now = Date()
        if let last = refreshedAt[appId], now.timeIntervalSince(last) < 60 { return }
        refreshedAt[appId] = now
        Task { [weak self] in
            let stats = await store.appStats(appBundleId: appId, days: 7)
            self?.cache[appId] = stats
        }
    }

    /// Сбросить кэш (очистка событий / выключение телеметрии).
    func invalidate() {
        cache.removeAll()
        refreshedAt.removeAll()
    }
}
