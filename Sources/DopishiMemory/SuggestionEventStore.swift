import Foundation
import GRDB
import DopishiCore

// MARK: - GRDB Row

private struct SuggestionEventRow: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var threadKey: String
    var appBundleId: String?
    var outcome: String
    var refusalReason: String?
    var latencyFirstMs: Int?
    var latencyTotalMs: Int?
    var modelFile: String?
    var promptMode: String?
    var kind: String?
    var createdAt: Double   // timeIntervalSince1970

    static let databaseTableName = "suggestion_event"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(_ e: SuggestionEvent) {
        self.threadKey = e.threadKey
        self.appBundleId = e.appBundleId
        self.outcome = e.outcome
        self.refusalReason = e.refusalReason
        self.latencyFirstMs = e.latencyFirstMs
        self.latencyTotalMs = e.latencyTotalMs
        self.modelFile = e.modelFile
        self.promptMode = e.promptMode
        self.kind = e.kind
        self.createdAt = e.createdAt.timeIntervalSince1970
    }
}

// MARK: - Actor

/// Хранилище событий жизненного цикла подсказок. Использует тот же DatabaseQueue что
/// MemoryStore (один memory.sqlite). Privacy: только метаданные, без сырого текста.
/// Async-write не блокирует вызывающий контекст (горячий путь, @MainActor).
public actor SuggestionEventStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Write

    /// Async-запись события. try? - провал записи телеметрии не должен валить пайплайн.
    public func record(_ event: SuggestionEvent) async {
        try? await dbQueue.write { db in
            var row = SuggestionEventRow(event)
            try row.insert(db)
        }
    }

    // MARK: - Read

    /// p50/p95 latencyFirstMs за окно дней. Только shown с непустой латентностью:
    /// accepted несёт ТОТ ЖЕ замер из кэша своего shown - включать его значило бы учесть
    /// одно измерение дважды и сместить p50/p95 к латентностям принятых подсказок.
    /// appBundleId == nil -> все приложения. Зовётся при открытии диагностики, не на hot-path.
    public func percentiles(appBundleId: String?, days: Int = 7, now: Date = Date()) async -> (p50: Int, p95: Int) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let values: [Int] = (try? await dbQueue.read { db -> [Int] in
            var request = SuggestionEventRow
                .filter(Column("outcome") == "shown")
                .filter(Column("latencyFirstMs") != nil)
                .filter(Column("createdAt") >= cutoff)
            if let app = appBundleId {
                request = request.filter(Column("appBundleId") == app)
            }
            return try request.fetchAll(db).compactMap(\.latencyFirstMs)
        }) ?? []
        return LatencyStats.percentiles(values)
    }

    /// p50/p95 latencyTotalMs за окно дней (весь стрим). Для DiagnosticsView.
    /// Только shown - по той же причине, что percentiles (accepted дублирует замер shown).
    /// appBundleId == nil -> все приложения. Зовётся при открытии диагностики, не на hot-path.
    public func percentilesTotal(appBundleId: String?, days: Int = 7, now: Date = Date()) async -> (p50: Int, p95: Int) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let values: [Int] = (try? await dbQueue.read { db -> [Int] in
            var request = SuggestionEventRow
                .filter(Column("outcome") == "shown")
                .filter(Column("latencyTotalMs") != nil)
                .filter(Column("createdAt") >= cutoff)
            if let app = appBundleId {
                request = request.filter(Column("appBundleId") == app)
            }
            return try request.fetchAll(db).compactMap(\.latencyTotalMs)
        }) ?? []
        return LatencyStats.percentiles(values)
    }

    /// Сводка per-app за окно дней (MEM-02, adaptive policy): зрелость статистики (total),
    /// shown/accepted для acceptance rate, последняя активность для decay.
    public func appStats(appBundleId: String, days: Int = 7, now: Date = Date()) async -> AppSuggestStats {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        return (try? await dbQueue.read { db -> AppSuggestStats in
            let rows = try SuggestionEventRow
                .filter(Column("appBundleId") == appBundleId)
                .filter(Column("createdAt") >= cutoff)
                .fetchAll(db)
            let shown = rows.count { $0.outcome == SuggestionEventOutcome.shown.rawValue }
            let accepted = rows.count { $0.outcome == SuggestionEventOutcome.accepted.rawValue }
            let lastAt = rows.map(\.createdAt).max().map { Date(timeIntervalSince1970: $0) }
            return AppSuggestStats(total: rows.count, shown: shown,
                                   accepted: accepted, lastEventAt: lastAt)
        }) ?? AppSuggestStats(total: 0, shown: 0, accepted: 0, lastEventAt: nil)
    }

    /// Распределение причин отказа (refusalReason) за окно дней. Для DiagnosticsView (DATA-03).
    public func refusalCounts(days: Int = 7, now: Date = Date()) async -> [String: Int] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let reasons: [String] = (try? await dbQueue.read { db -> [String] in
            try SuggestionEventRow
                .filter(Column("refusalReason") != nil)
                .filter(Column("createdAt") >= cutoff)
                .fetchAll(db).compactMap(\.refusalReason)
        }) ?? []
        return reasons.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    // MARK: - Maintenance

    /// Удалить события старше N дней (TTL, default 7). Возвращает кол-во удалённых.
    @discardableResult
    public func prune(days: Int = 7, now: Date = Date()) async -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        return (try? await dbQueue.write { db in
            try SuggestionEventRow.filter(Column("createdAt") < cutoff).deleteAll(db)
        }) ?? 0
    }

    /// Удалить ВСЕ события (Privacy Center / onClearMemory - чистим рядом с памятью).
    public func clearAll() async {
        try? await dbQueue.write { db in
            _ = try SuggestionEventRow.deleteAll(db)
        }
    }

    /// Кол-во событий (тесты/диагностика).
    public func count() async -> Int {
        (try? await dbQueue.read { db in try SuggestionEventRow.fetchCount(db) }) ?? 0
    }
}
