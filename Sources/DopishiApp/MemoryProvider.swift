import AppKit
import DopishiCore
import DopishiMemory
import GRDB

/// Оркестратор локальной памяти контекста. Держит MemoryStore (на диске в App Support),
/// пишет на смену потока (исходящий текст) и держит latest - готовый снимок канала «Память:»
/// для текущего потока. Генерация подсказки НИКОГДА не ждёт БД - берёт latest или nil.
/// Все операции с БД - в фоне (Task.detached), как у WindowOCRProvider.
@MainActor
final class MemoryProvider {
    var enabled = false {
        didSet { if !enabled { latest = nil } }
    }
    /// TTL записей в днях (Privacy Center, UX-02). Default 7 - решение вехи.
    var ttlDays = 7
    /// «Не учиться в этом приложении» (Privacy Center): запись памяти из этих bundleId
    /// блокируется; подсказки в них продолжают работать.
    var learningExcluded: Set<String> = []
    private(set) var latest: String?

    private var store: MemoryStore?
    /// Наблюдаемость secret-drop (D-06). Слабая ссылка - DiagnosticsCenter живёт в App.
    /// Инъекция (memoryProvider.setDiagnostics) делается из AppDelegate (Plan 08-04).
    private weak var diagnostics: DiagnosticsCenter?
    private var currentThreadKey: String?
    private var lastRecorded: [String: String] = [:]   // дедуп записи по потоку
    /// Дебаунс FTS-пересчёта снимка (MEM-01): последний собранный MATCH-запрос и время.
    private var lastFTSQuery = ""
    private var lastFTSAt = Date.distantPast

    /// Подключить DiagnosticsCenter для наблюдаемости secret-drop (D-06). По образцу
    /// DiagnosticsCenter.setEventStore - так App-классы получают зависимости. Фактический
    /// вызов из AppDelegate выполняет Plan 08-04 (этот план только объявляет проводку).
    func setDiagnostics(_ d: DiagnosticsCenter?) { diagnostics = d }

    private func ensureStore() -> MemoryStore? {
        if let store { return store }
        guard let dir = Self.supportDir() else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let dbPath = dir.appendingPathComponent("memory.sqlite").path
        store = try? MemoryStore.onDisk(path: dbPath)
        // Память персистится на диск - ограничиваем доступ владельцем (каталог 0700, файл 0600),
        // чтобы сырое чтение диска другим пользователем не выдало содержимое.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        if store != nil { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath) }
        return store
    }

    private static func supportDir() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Dopishi", isDirectory: true)
    }

    /// Записать текст потока (вызывается на уходе из потока). Секрет-дроп + дедуп + фон.
    /// Вызывающий обязан передавать только allowed + non-secure текст. Гейт «не учиться
    /// в этом приложении» - здесь (по bundleId из threadKey), инкапсулирован в провайдере.
    func record(threadKey: String, kind: MemoryKind = .message, text: String) {
        guard enabled else { return }
        if let bid = Self.bundleId(fromThreadKey: threadKey), learningExcluded.contains(bid) { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        if SecretGuard.looksSecret(t) { diagnostics?.noteSecretDropped(); return }   // D-06: только счётчик, не текст
        guard lastRecorded[threadKey] != t else { return }   // не дублируем подряд тот же текст
        if lastRecorded.count >= 128 { lastRecorded.removeAll() }   // защита от роста за сессию
        lastRecorded[threadKey] = t
        guard let store = ensureStore() else { return }
        let ttl = Double(max(1, ttlDays)) * 86400
        Task.detached(priority: .utility) {
            try? store.record(threadKey: threadKey, kind: kind, text: t, ttl: ttl)
        }
    }

    /// bundleId из threadKey "bundleId:windowId" (всё до ПОСЛЕДНЕГО двоеточия - windowId
    /// числовой и двоеточий не содержит, сам bundleId содержать может).
    private static func bundleId(fromThreadKey key: String) -> String? {
        guard let idx = key.lastIndex(of: ":") else { return nil }
        let bid = String(key[key.startIndex..<idx])
        return (bid.isEmpty || bid == "?") ? nil : bid
    }

    /// DatabaseQueue общей базы памяти - для SuggestionEventStore (один memory.sqlite).
    /// Внимание: обращение лениво создаёт memory.sqlite (ensureStore). Звать только под гейтом
    /// телеметрии (AppDelegate), иначе материализуем базу при выключенной памяти - регресс privacy.
    var storeQueue: DatabaseQueue? { ensureStore()?.queue }

    /// Сменить текущий поток - пересчитать снимок «Память:» (фоном). nil-ключ -> снимок пуст.
    func setCurrentThread(_ key: String?) {
        currentThreadKey = key
        lastFTSQuery = ""   // новый поток - FTS-дебаунс с чистого листа
        guard enabled, let key, let store = ensureStore() else { latest = nil; return }
        Task.detached(priority: .utility) { [weak self] in
            _ = try? store.prune()   // TTL чистим на каждую смену потока (дёшево, фоном)
            let items = (try? store.recentItems(threadKey: key, limit: 12)) ?? []
            let text = MemoryRetrieval.format(items)
            await self?.applySnapshot(key: key, text: text.isEmpty ? nil : text)
        }
    }

    /// Обновить снимок «Память:» под набираемый текст (MEM-01): FTS5 достаёт релевантное
    /// старое, recency - свежее; formatMixed смешивает. Контракт сохранён: генерация НЕ
    /// ждёт БД - снимок обновляется фоном и подхватывается следующим keystroke.
    /// Дебаунс: пересчёт только при смене последних слов запроса и не чаще раза в 0.7с.
    func noteTypingPrefix(_ prefix: String) {
        guard enabled, let key = currentThreadKey else { return }
        let query = MemoryStore.ftsQuery(from: prefix)
        guard !query.isEmpty, query != lastFTSQuery else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFTSAt) > 0.7 else { return }
        lastFTSQuery = query
        lastFTSAt = now
        guard let store = ensureStore() else { return }
        Task.detached(priority: .utility) { [weak self] in
            let recent = (try? store.recentItems(threadKey: key, limit: 12)) ?? []
            let relevant = (try? store.relevantItems(threadKey: key, query: prefix, limit: 6)) ?? []
            let text = MemoryRetrieval.formatMixed(recent: recent, relevant: relevant)
            await self?.applySnapshot(key: key, text: text.isEmpty ? nil : text)
        }
    }

    private func applySnapshot(key: String, text: String?) {
        guard key == currentThreadKey else { return }   // поток сменился, пока читали - снимок устарел
        latest = text
    }

    /// Очистить всю память (кнопка настроек).
    /// Тексты для предиктора (PERF-03): принятые подсказки + записи окон, новые первыми.
    /// Пусто при выключенной памяти (SC-5: предиктор - функция opt-in пользователей).
    func predictorTexts(limit: Int = 300) -> [String] {
        guard enabled, let store = ensureStore() else { return [] }
        return (try? store.recentTexts(limit: limit)) ?? []
    }

    func clear() {
        latest = nil
        lastRecorded.removeAll()
        guard let store = ensureStore() else { return }
        Task.detached(priority: .utility) { try? store.clearAll() }
    }

    func invalidate() { latest = nil }

    // MARK: - Privacy Center (UX-02)

    /// Размер базы памяти на диске (байты). nil - база ещё не материализована.
    /// НЕ зовёт ensureStore: не создаём файл ради показа размера.
    func dbSizeBytes() -> Int64? {
        guard let dir = Self.supportDir() else { return nil }
        let path = dir.appendingPathComponent("memory.sqlite").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? NSNumber else { return nil }
        return bytes.int64Value
    }

    /// Экспорт всех НЕистёкших записей в JSON (кнопка «Экспортировать память»).
    /// Фоном (БД + сериализация не на главном).
    func exportJSON() async -> Data? {
        guard let store = ensureStore() else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let items = try? store.exportItems() else { return nil }
            let rows = items.map { item in
                ExportRow(threadKey: item.threadKey, kind: item.kind.rawValue, text: item.text,
                          createdAt: ISO8601DateFormatter().string(from: item.createdAt),
                          expiresAt: item.expiresAt.map { ISO8601DateFormatter().string(from: $0) })
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(rows)
        }.value
    }

    private struct ExportRow: Codable {
        let threadKey: String
        let kind: String
        let text: String
        let createdAt: String
        let expiresAt: String?
    }
}
