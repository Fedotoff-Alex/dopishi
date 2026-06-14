import Testing
import Foundation
@testable import DopishiMemory

@Suite struct MemoryStoreTests {
    private func store() throws -> MemoryStore { try MemoryStore.inMemory() }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func recordAndFetchNewestFirst() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "первое", now: t0)
        try s.record(threadKey: "app:1", kind: .message, text: "второе", now: t0.addingTimeInterval(10))
        try s.record(threadKey: "app:1", kind: .accepted, text: "третье", now: t0.addingTimeInterval(20))
        let items = try s.recentItems(threadKey: "app:1", limit: 12, now: t0.addingTimeInterval(30))
        #expect(items.map(\.text) == ["третье", "второе", "первое"])
        #expect(items[0].kind == .accepted)
    }

    @Test func threadScoping() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "из потока 1", now: t0)
        try s.record(threadKey: "app:2", kind: .message, text: "из потока 2", now: t0)
        let items = try s.recentItems(threadKey: "app:1", now: t0.addingTimeInterval(5))
        #expect(items.map(\.text) == ["из потока 1"])
    }

    @Test func expiredExcludedFromFetch() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "устареет", now: t0, ttl: 100)
        try s.record(threadKey: "app:1", kind: .message, text: "свежее", now: t0, ttl: 10_000)
        let items = try s.recentItems(threadKey: "app:1", now: t0.addingTimeInterval(200))
        #expect(items.map(\.text) == ["свежее"])
    }

    @Test func pruneDeletesExpired() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "истёкшее", now: t0, ttl: 100)
        try s.record(threadKey: "app:1", kind: .message, text: "живое", now: t0, ttl: 10_000)
        let deleted = try s.prune(now: t0.addingTimeInterval(200))
        #expect(deleted == 1)
        #expect(try s.count() == 1)
    }

    @Test func nilTTLNeverExpires() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "вечное", now: t0, ttl: nil)
        let items = try s.recentItems(threadKey: "app:1", now: t0.addingTimeInterval(10_000_000))
        #expect(items.map(\.text) == ["вечное"])
        #expect(try s.prune(now: t0.addingTimeInterval(10_000_000)) == 0)
    }

    @Test func clearAllEmpties() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "a", now: t0)
        try s.record(threadKey: "app:2", kind: .message, text: "b", now: t0)
        try s.clearAll()
        #expect(try s.count() == 0)
    }

    @Test func emptyTextIgnored() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "   \n  ", now: t0)
        #expect(try s.count() == 0)
    }

    /// Privacy Center (UX-02): экспорт - все НЕистёкшие записи всех потоков, новейшие первыми.
    @Test func exportItemsAllThreadsNewestFirstSkipsExpired() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "старое", now: t0)
        try s.record(threadKey: "app:2", kind: .accepted, text: "новое", now: t0.addingTimeInterval(10))
        try s.record(threadKey: "app:1", kind: .message, text: "истёкшее", now: t0, ttl: 5)
        let items = try s.exportItems(now: t0.addingTimeInterval(20))
        #expect(items.map(\.text) == ["новое", "старое"])
        #expect(items.map(\.threadKey) == ["app:2", "app:1"])
    }

    @Test func limitRespected() throws {
        let s = try store()
        for i in 0..<20 {
            try s.record(threadKey: "app:1", kind: .message, text: "n\(i)",
                         now: t0.addingTimeInterval(Double(i)))
        }
        let items = try s.recentItems(threadKey: "app:1", limit: 5, now: t0.addingTimeInterval(100))
        #expect(items.count == 5)
        #expect(items.first?.text == "n19")   // новейший
    }

    @Test func v2MigrationKeepsContextItems() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "выжил после v2", now: t0)
        // запись в suggestion_event идёт через SuggestionEventStore (Plan 02 Task 2),
        // здесь проверяем что v1-данные не потеряны после применения v2-миграции в init
        let items = try s.recentItems(threadKey: "app:1", now: t0.addingTimeInterval(5))
        #expect(items.map(\.text) == ["выжил после v2"])
    }
}
