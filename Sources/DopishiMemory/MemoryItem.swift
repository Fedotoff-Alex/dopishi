import Foundation

/// Вид элемента памяти.
public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case message    // готовое сообщение/строка пользователя (после Enter/границы)
    case accepted   // принятая подсказка (Tab)
}

/// Элемент локальной памяти контекста (одна запись диалога/потока).
public struct MemoryItem: Equatable, Sendable {
    public let id: Int64?
    public let threadKey: String   // ключ потока: "<bundleId>:<windowId>" (диалог/окно)
    public let kind: MemoryKind
    public let text: String
    public let createdAt: Date
    public let expiresAt: Date?    // TTL: после этого момента запись удаляется prune()

    public init(id: Int64? = nil, threadKey: String, kind: MemoryKind, text: String,
                createdAt: Date, expiresAt: Date? = nil) {
        self.id = id
        self.threadKey = threadKey
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}
