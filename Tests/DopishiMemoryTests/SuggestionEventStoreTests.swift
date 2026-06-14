import Testing
import Foundation
import GRDB
@testable import DopishiMemory
@testable import DopishiCore

@Suite struct SuggestionEventStoreTests {
    private func makeStore() throws -> SuggestionEventStore {
        let ms = try MemoryStore.inMemory()
        return SuggestionEventStore(dbQueue: ms.queue)
    }

    private func event(_ outcome: String, first: Int?, app: String? = "com.test",
                       refusal: String? = nil, kind: String? = "completion",
                       at: Date = Date()) -> SuggestionEvent {
        SuggestionEvent(threadKey: "\(app ?? "?"):1", appBundleId: app, outcome: outcome,
                        refusalReason: refusal, latencyFirstMs: first,
                        latencyTotalMs: first.map { $0 + 100 },
                        modelFile: "m.gguf", promptMode: nil, kind: kind, createdAt: at)
    }

    @Test func recordAndPercentiles() async throws {
        let s = try makeStore()
        await s.record(event("shown", first: 150))
        let (p50, p95) = await s.percentiles(appBundleId: "com.test")
        #expect(p50 == 150)
        #expect(p95 == 150)
        // percentilesTotal: latencyTotalMs = first + 100 = 250 (Plan 04 вызывает эту функцию)
        let (t50, _) = await s.percentilesTotal(appBundleId: "com.test")
        #expect(t50 == 250)
    }

    @Test func percentilesIgnoreDismissedAndRefused() async throws {
        let s = try makeStore()
        await s.record(event("shown", first: 100))
        await s.record(event("dismissed", first: 999))
        await s.record(event("refused", first: nil, refusal: "belowMinChars", kind: nil))
        let (p50, _) = await s.percentiles(appBundleId: "com.test")
        #expect(p50 == 100)   // только shown попало
    }

    @Test func percentilesExcludeAccepted() async throws {
        // WR-01: accepted несёт тот же замер, что его shown (latency-кэш) - в перцентили
        // идёт только shown, иначе одно измерение учлось бы дважды.
        let s = try makeStore()
        await s.record(event("shown", first: 100))
        await s.record(event("accepted", first: 100))   // та же подсказка, тот же замер
        await s.record(event("shown", first: 300))
        let (p50, _) = await s.percentiles(appBundleId: "com.test")
        #expect(p50 == 300)   // выборка [100, 300]; с дублем от accepted было бы 100
        let (t50, _) = await s.percentilesTotal(appBundleId: "com.test")
        #expect(t50 == 400)   // totalMs = first + 100: выборка [200, 400]; с дублем было бы 200
    }

    @Test func refusalCountsAggregated() async throws {
        let s = try makeStore()
        await s.record(event("refused", first: nil, refusal: "belowMinChars", kind: nil))
        await s.record(event("refused", first: nil, refusal: "belowMinChars", kind: nil))
        await s.record(event("refused", first: nil, refusal: "emptyText", kind: nil))
        let counts = await s.refusalCounts()
        #expect(counts["belowMinChars"] == 2)
        #expect(counts["emptyText"] == 1)
    }

    @Test func pruneDeletesOldEvents() async throws {
        let s = try makeStore()
        let old = Date().addingTimeInterval(-10 * 86400)   // 10 дней назад
        await s.record(event("shown", first: 120, at: old))
        await s.record(event("shown", first: 130))         // свежее
        let deleted = await s.prune(days: 7)
        #expect(deleted == 1)
        #expect(await s.count() == 1)
    }

    @Test func percentilesNilAppAggregatesAll() async throws {
        let s = try makeStore()
        await s.record(event("shown", first: 100, app: "com.a"))
        await s.record(event("shown", first: 200, app: "com.b"))
        let (p50, _) = await s.percentiles(appBundleId: nil)
        #expect(p50 > 0)
    }

    @Test func percentilesWindowExcludesOld() async throws {
        let s = try makeStore()
        let old = Date().addingTimeInterval(-10 * 86400)   // вне окна days:7
        await s.record(event("shown", first: 500, at: old))
        await s.record(event("shown", first: 120))         // в окне
        let (p50, _) = await s.percentiles(appBundleId: "com.test", days: 7)
        #expect(p50 == 120)   // старое (500) НЕ попало в окно
    }

    @Test func clearAllRemovesEverything() async throws {
        let s = try makeStore()
        await s.record(event("shown", first: 100))
        await s.record(event("accepted", first: 110))
        await s.clearAll()
        #expect(await s.count() == 0)
    }

    /// MEM-02: per-app сводка для adaptive policy - total/shown/accepted/lastEventAt,
    /// только события своего приложения и только в окне.
    @Test func appStatsAggregatesPerAppWithinWindow() async throws {
        let s = try makeStore()
        await s.record(event("shown", first: 100))
        await s.record(event("shown", first: 120))
        await s.record(event("accepted", first: 100))
        await s.record(event("refused", first: nil, refusal: "belowMinChars", kind: nil))
        await s.record(event("shown", first: 90, app: "com.other"))            // чужое приложение
        let old = Date().addingTimeInterval(-10 * 86400)
        await s.record(event("shown", first: 500, at: old))                    // вне окна 7 дней
        let stats = await s.appStats(appBundleId: "com.test", days: 7)
        #expect(stats.total == 4)
        #expect(stats.shown == 2)
        #expect(stats.accepted == 1)
        #expect(stats.lastEventAt != nil)
    }

    @Test func appStatsEmptyForUnknownApp() async throws {
        let s = try makeStore()
        let stats = await s.appStats(appBundleId: "com.nothing")
        #expect(stats == AppSuggestStats(total: 0, shown: 0, accepted: 0, lastEventAt: nil))
    }

    /// Phase 4 SC-4: suggestion_event - только метаданные. В схеме нет open-text колонок
    /// с пользовательским текстом (prefixTail/precedingText/suggestionText и подобных);
    /// фиксируем ТОЧНЫЙ список колонок - новая колонка с текстом завалит тест осознанно.
    @Test func suggestionEventSchemaIsMetadataOnly() throws {
        let ms = try MemoryStore.inMemory()
        let columns: Set<String> = try ms.queue.read { db in
            Set(try Row.fetchAll(db, sql: "PRAGMA table_info(suggestion_event)")
                .map { $0["name"] as String })
        }
        let allowed: Set<String> = ["id", "threadKey", "appBundleId", "outcome",
                                    "refusalReason", "latencyFirstMs", "latencyTotalMs",
                                    "modelFile", "promptMode", "kind", "createdAt"]
        #expect(columns == allowed)
    }
}
