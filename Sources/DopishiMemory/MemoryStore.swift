import Foundation
import GRDB
import DopishiCore

/// Локальное хранилище памяти контекста на SQLite (через GRDB). Живёт на диске
/// (~/Library/Application Support/Dopishi/memory.sqlite) или в памяти (тесты).
/// DatabaseQueue сериализует доступ и потокобезопасен - можно звать с фонового контекста.
///
/// Приватность: вызывающий обязан НЕ записывать secure-поля и секреты (это делает MemoryProvider).
public final class MemoryStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    /// TTL по умолчанию - 14 дней. Старее prune() удаляет.
    public static let defaultTTL: TimeInterval = 14 * 24 * 3600

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// Хранилище на диске по пути файла (директория должна существовать).
    public static func onDisk(path: String) throws -> MemoryStore {
        try MemoryStore(dbQueue: try DatabaseQueue(path: path))
    }

    /// In-memory хранилище (для тестов).
    public static func inMemory() throws -> MemoryStore {
        try MemoryStore(dbQueue: try DatabaseQueue())
    }

    /// Тот же DatabaseQueue для SuggestionEventStore (один memory.sqlite, один queue).
    /// package: виден между таргетами пакета (DopishiMemory <-> DopishiApp), не public наружу.
    package var queue: DatabaseQueue { dbQueue }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_context_items") { db in
            try db.create(table: "context_item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("threadKey", .text).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("expiresAt", .double)
            }
        }
        m.registerMigration("v2_suggestion_events") { db in
            try db.create(table: "suggestion_event") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("threadKey", .text).notNull()
                t.column("appBundleId", .text)
                t.column("outcome", .text).notNull()
                t.column("refusalReason", .text)
                t.column("latencyFirstMs", .integer)
                t.column("latencyTotalMs", .integer)
                t.column("modelFile", .text)
                t.column("promptMode", .text)
                t.column("kind", .text)              // класс подсказки: "completion" | NULL
                t.column("createdAt", .double).notNull()
            }
            try db.create(indexOn: "suggestion_event", columns: ["appBundleId", "createdAt"])
        }
        // MEM-01 (Phase 6): полнотекстовый индекс по context_item.text. External content
        // (данные живут в context_item, индекс не дублирует текст) + триггеры синхронизации.
        // unicode61 фолдит кириллицу к нижнему регистру (MATCH регистронезависимый) -
        // фиксируется integration-тестом cyrillicMixedCaseMatch.
        m.registerMigration("v3_fts") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE context_item_fts USING fts5(
                    text,
                    content='context_item',
                    content_rowid='id',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER context_item_fts_ai AFTER INSERT ON context_item BEGIN
                    INSERT INTO context_item_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER context_item_fts_ad AFTER DELETE ON context_item BEGIN
                    INSERT INTO context_item_fts(context_item_fts, rowid, text)
                    VALUES ('delete', old.id, old.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER context_item_fts_au AFTER UPDATE ON context_item BEGIN
                    INSERT INTO context_item_fts(context_item_fts, rowid, text)
                    VALUES ('delete', old.id, old.text);
                    INSERT INTO context_item_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
            // Бэкфилл существующих записей в индекс.
            try db.execute(sql: "INSERT INTO context_item_fts(context_item_fts) VALUES ('rebuild')")
        }
        return m
    }

    /// Записать элемент. ttl=nil -> defaultTTL. Пустой/пробельный текст игнорируется.
    public func record(threadKey: String, kind: MemoryKind, text: String,
                       now: Date = Date(), ttl: TimeInterval? = MemoryStore.defaultTTL) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !SecretGuard.looksSecret(trimmed) else { return }   // ВОРОНКА 1: дроп целиком (D-04)
        let expires = ttl.map { now.addingTimeInterval($0) }
        try dbQueue.write { db in
            var row = ContextItemRow(id: nil, threadKey: threadKey, kind: kind.rawValue,
                                     text: trimmed, createdAt: now.timeIntervalSince1970,
                                     expiresAt: expires?.timeIntervalSince1970)
            try row.insert(db)
        }
    }

    /// Недавние НЕистёкшие элементы потока, новейшие первыми (до limit).
    public func recentItems(threadKey: String, limit: Int = 12, now: Date = Date()) throws -> [MemoryItem] {
        let nowTs = now.timeIntervalSince1970
        let rows = try dbQueue.read { db in
            try ContextItemRow
                .filter(Column("threadKey") == threadKey)
                .filter(Column("expiresAt") == nil || Column("expiresAt") > nowTs)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return rows.map { $0.toItem() }
    }

    /// Свежие НЕистёкшие тексты по ВСЕМ потокам (для предиктора, PERF-03), новые первыми.
    public func recentTexts(limit: Int = 300, now: Date = Date()) throws -> [String] {
        let nowTs = now.timeIntervalSince1970
        let rows = try dbQueue.read { db in
            try ContextItemRow
                .filter(Column("expiresAt") == nil || Column("expiresAt") > nowTs)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
        return rows.map { $0.text }
    }

    /// Удалить истёкшие записи (по expiresAt < now).
    @discardableResult
    public func prune(now: Date = Date()) throws -> Int {
        let nowTs = now.timeIntervalSince1970
        return try dbQueue.write { db in
            try ContextItemRow
                .filter(Column("expiresAt") != nil && Column("expiresAt") < nowTs)
                .deleteAll(db)
        }
    }

    /// Релевантные НЕистёкшие записи потока по FTS5 (MEM-01), новейшие первыми.
    /// `query` - сырой текст (хвост набора): билдер берёт последние значимые слова
    /// prefix-запросом. Пустой собранный запрос -> [] без обращения к БД.
    public func relevantItems(threadKey: String, query: String, limit: Int = 6,
                              now: Date = Date()) throws -> [MemoryItem] {
        let match = Self.ftsQuery(from: query)
        guard !match.isEmpty else { return [] }
        let nowTs = now.timeIntervalSince1970
        let rows = try dbQueue.read { db in
            try ContextItemRow.fetchAll(db, sql: """
                SELECT * FROM context_item
                WHERE id IN (SELECT rowid FROM context_item_fts WHERE context_item_fts MATCH ?)
                  AND threadKey = ?
                  AND (expiresAt IS NULL OR expiresAt > ?)
                ORDER BY createdAt DESC
                LIMIT ?
                """, arguments: [match, threadKey, nowTs, limit])
        }
        return rows.map { $0.toItem() }
    }

    /// Безопасный FTS5 MATCH из сырого текста: последние maxTerms слов длиной >=3,
    /// каждое - prefix-запрос в кавычках ("слово"*), OR-семантика (достаточно одного
    /// совпадения). Кавычки в словах невозможны (split по не-буквам), но вырезаются
    /// страховочно - синтаксис MATCH сломать нельзя.
    public static func ftsQuery(from raw: String, maxTerms: Int = 3) -> String {
        let words = raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
            .suffix(maxTerms)
        guard !words.isEmpty else { return "" }
        return words
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
            .joined(separator: " OR ")
    }

    /// Все НЕистёкшие записи всех потоков, новейшие первыми (Privacy Center: «Экспортировать»).
    public func exportItems(now: Date = Date()) throws -> [MemoryItem] {
        let nowTs = now.timeIntervalSince1970
        let rows = try dbQueue.read { db in
            try ContextItemRow
                .filter(Column("expiresAt") == nil || Column("expiresAt") > nowTs)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
        return rows.map { $0.toItem() }
    }

    /// Полностью очистить память (кнопка «Очистить память»).
    public func clearAll() throws {
        _ = try dbQueue.write { db in try ContextItemRow.deleteAll(db) }
    }

    /// Кол-во записей (диагностика/тесты).
    public func count() throws -> Int {
        try dbQueue.read { db in try ContextItemRow.fetchCount(db) }
    }
}

/// Строка таблицы context_item (GRDB-маппинг). Даты - Double (timeIntervalSince1970).
private struct ContextItemRow: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var threadKey: String
    var kind: String
    var text: String
    var createdAt: Double
    var expiresAt: Double?

    static let databaseTableName = "context_item"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func toItem() -> MemoryItem {
        MemoryItem(id: id, threadKey: threadKey,
                   kind: MemoryKind(rawValue: kind) ?? .message,
                   text: text, createdAt: Date(timeIntervalSince1970: createdAt),
                   expiresAt: expiresAt.map { Date(timeIntervalSince1970: $0) })
    }
}
