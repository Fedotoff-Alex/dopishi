import AppKit
import DopishiCore
import DopishiMemory

/// Оркестратор локальной памяти контекста. Держит MemoryStore (на диске в App Support),
/// пишет на смену потока (исходящий текст) и держит latest - готовый снимок канала «Память:»
/// для текущего потока. Генерация подсказки НИКОГДА не ждёт БД - берёт latest или nil.
/// Все операции с БД - в фоне (Task.detached), как у WindowOCRProvider.
@MainActor
final class MemoryProvider {
    var enabled = false {
        didSet { if !enabled { latest = nil } }
    }
    private(set) var latest: String?

    private var store: MemoryStore?
    private var currentThreadKey: String?
    private var lastRecorded: [String: String] = [:]   // дедуп записи по потоку

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
    /// Вызывающий обязан передавать только allowed + non-secure текст.
    func record(threadKey: String, text: String) {
        guard enabled else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !ClipboardContentDistiller.looksSecret(t) else { return }
        guard lastRecorded[threadKey] != t else { return }   // не дублируем подряд тот же текст
        if lastRecorded.count >= 128 { lastRecorded.removeAll() }   // защита от роста за сессию
        lastRecorded[threadKey] = t
        guard let store = ensureStore() else { return }
        Task.detached(priority: .utility) {
            try? store.record(threadKey: threadKey, kind: .message, text: t)
        }
    }

    /// Сменить текущий поток - пересчитать снимок «Память:» (фоном). nil-ключ -> снимок пуст.
    func setCurrentThread(_ key: String?) {
        currentThreadKey = key
        guard enabled, let key, let store = ensureStore() else { latest = nil; return }
        Task.detached(priority: .utility) { [weak self] in
            _ = try? store.prune()   // TTL чистим на каждую смену потока (дёшево, фоном)
            let items = (try? store.recentItems(threadKey: key, limit: 12)) ?? []
            let text = MemoryRetrieval.format(items)
            await self?.applySnapshot(key: key, text: text.isEmpty ? nil : text)
        }
    }

    private func applySnapshot(key: String, text: String?) {
        guard key == currentThreadKey else { return }   // поток сменился, пока читали - снимок устарел
        latest = text
    }

    /// Очистить всю память (кнопка настроек).
    func clear() {
        latest = nil
        lastRecorded.removeAll()
        guard let store = ensureStore() else { return }
        Task.detached(priority: .utility) { try? store.clearAll() }
    }

    func invalidate() { latest = nil }
}
