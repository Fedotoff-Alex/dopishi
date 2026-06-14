import Foundation
import DopishiCore

/// Превращает элементы памяти в строку канала «Память:» для промпта.
/// Чистая логика (тестируемо): берёт новейшие в пределах бюджета, отдаёт в ХРОНОЛОГИЧЕСКОМ
/// порядке (старое->новое - естественно читается как продолжение диалога), санитайзит.
public enum MemoryRetrieval {
    /// - Parameters:
    ///   - items: элементы потока, НОВЕЙШИЕ ПЕРВЫМИ (как отдаёт MemoryStore.recentItems).
    ///   - maxChars: бюджет символов канала.
    /// - Returns: строка для «Память:» либо "" если нечего показать.
    public static func format(_ items: [MemoryItem], maxChars: Int = 600) -> String {
        var taken: [String] = []
        var count = 0
        for item in items {   // новейшие первыми - набираем, пока влезает в бюджет
            let t = PromptContextSanitizer.sanitize(item.text)
            guard !t.isEmpty else { continue }
            // Новейший элемент один больше бюджета - берём его голову (иначе канал был бы пуст).
            if taken.isEmpty, t.count > maxChars {
                taken.append(String(t.prefix(maxChars)))
                break
            }
            if count + t.count + 1 > maxChars { break }
            taken.append(t)
            count += t.count + 1
        }
        // Разворот -> хронологический порядок (старое -> новое).
        return taken.reversed().joined(separator: " ")
    }

    /// Микс «свежее + релевантное» (MEM-01): к свежим записям потока добавляются
    /// FTS5-находки по набираемому тексту - старое-но-в-тему всплывает, чего
    /// recency-only не умел. Дедуп по тексту, общая сортировка по времени (новейшие
    /// первыми), дальше тот же бюджет/порядок, что у format().
    public static func formatMixed(recent: [MemoryItem], relevant: [MemoryItem],
                                   maxChars: Int = 600) -> String {
        var seen = Set<String>()
        var combined: [MemoryItem] = []
        for item in recent + relevant where seen.insert(item.text).inserted {
            combined.append(item)
        }
        combined.sort { $0.createdAt > $1.createdAt }
        return format(combined, maxChars: maxChars)
    }
}
