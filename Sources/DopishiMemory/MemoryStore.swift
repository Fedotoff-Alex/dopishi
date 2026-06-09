import Foundation
import GRDB

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
        return m
    }

    /// Записать элемент. ttl=nil -> defaultTTL. Пустой/пробельный текст игнорируется.
    public func record(threadKey: String, kind: MemoryKind, text: String,
                       now: Date = Date(), ttl: TimeInterval? = MemoryStore.defaultTTL) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
