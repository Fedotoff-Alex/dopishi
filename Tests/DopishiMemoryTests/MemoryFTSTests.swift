import Testing
import Foundation
@testable import DopishiMemory

/// MEM-01 (Phase 6): FTS5-поиск релевантных записей памяти.
/// КРИТЕРИЙ ВЕХИ: кириллица находится в ЛЮБОМ регистре (unicode61 case folding).
@Suite struct MemoryFTSTests {
    private func store() throws -> MemoryStore { try MemoryStore.inMemory() }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func cyrillicMixedCaseMatch() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "Привет МИР как дела", now: t0)
        let byLower = try s.relevantItems(threadKey: "app:1", query: "мир", now: t0.addingTimeInterval(5))
        #expect(byLower.map(\.text) == ["Привет МИР как дела"])
        let byUpper = try s.relevantItems(threadKey: "app:1", query: "ПРИВЕТ", now: t0.addingTimeInterval(5))
        #expect(byUpper.map(\.text) == ["Привет МИР как дела"])
    }

    @Test func prefixMatchFindsLongerWord() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "купил новый велосипед вчера", now: t0)
        let items = try s.relevantItems(threadKey: "app:1", query: "вело", now: t0.addingTimeInterval(5))
        #expect(items.map(\.text) == ["купил новый велосипед вчера"])
    }

    @Test func threadScopedAndExpiredExcluded() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "велосипед из потока 1", now: t0)
        try s.record(threadKey: "app:2", kind: .message, text: "велосипед из потока 2", now: t0)
        try s.record(threadKey: "app:1", kind: .message, text: "велосипед истёкший", now: t0, ttl: 5)
        let items = try s.relevantItems(threadKey: "app:1", query: "велосипед", now: t0.addingTimeInterval(100))
        #expect(items.map(\.text) == ["велосипед из потока 1"])
    }

    @Test func newestFirstAndLimit() throws {
        let s = try store()
        for i in 0..<5 {
            try s.record(threadKey: "app:1", kind: .message, text: "проект номер \(i)",
                         now: t0.addingTimeInterval(Double(i)))
        }
        let items = try s.relevantItems(threadKey: "app:1", query: "проект", limit: 2,
                                        now: t0.addingTimeInterval(100))
        #expect(items.map(\.text) == ["проект номер 4", "проект номер 3"])
    }

    @Test func deletedRowsLeaveIndex() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "велосипед на удаление", now: t0)
        try s.clearAll()
        let items = try s.relevantItems(threadKey: "app:1", query: "велосипед", now: t0.addingTimeInterval(5))
        #expect(items.isEmpty)
    }

    /// Билдер FTS-запроса: последние слова >=3 букв, prefix-search, мусор не валит запрос.
    @Test func ftsQueryBuilder() {
        #expect(MemoryStore.ftsQuery(from: "привет мир") == "\"привет\"* OR \"мир\"*")
        #expect(MemoryStore.ftsQuery(from: "а б в") == "")          // все короче 3
        #expect(MemoryStore.ftsQuery(from: "") == "")
        // кавычка - не буква, работает сепаратором; синтаксис MATCH не ломается
        #expect(MemoryStore.ftsQuery(from: "ска\"зал") == "\"ска\"* OR \"зал\"*")
        // максимум 3 последних значимых слова
        #expect(MemoryStore.ftsQuery(from: "один два три четыре пять")
                == "\"три\"* OR \"четыре\"* OR \"пять\"*")
    }

    /// Запрос из одних коротких/пустых слов не делает SQL-вызова и не падает.
    @Test func emptyQueryReturnsNothing() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "что-то записано", now: t0)
        let items = try s.relevantItems(threadKey: "app:1", query: "и а", now: t0.addingTimeInterval(5))
        #expect(items.isEmpty)
    }
}
