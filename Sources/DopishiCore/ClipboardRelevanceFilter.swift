import Foundation

/// Решает, релевантен ли буфер обмена для подмешивания в промпт автодополнения.
/// Возвращает буфер БЕЗ изменений (релевантен) или nil (отбросить). Дистилляция/санитайз -
/// отдельно (ClipboardContentDistiller). Stateful: помнит changeCount и время последней копии,
/// чтобы не подмешивать ни предсуществующий буфер (до запуска), ни устаревший.
///
/// Собственная реализация: алгоритм (baseline changeCount + окно свежести + пересечение токенов) -
/// общеизвестный приём, выражается единственно-разумным образом.
/// Не Sendable намеренно: держится @MainActor-объектом (ContextProbe), за актор не уходит.
public final class ClipboardRelevanceFilter {
    /// Максимальный возраст последней копии для подмешивания (секунды).
    public static let staleThresholdSeconds: TimeInterval = 300
    private static let minimumTokenLength = 3

    private var lastKnownChangeCount: Int?
    private var lastChangeDate: Date?
    private let dateProvider: () -> Date

    public init(dateProvider: @escaping () -> Date = { Date() }) {
        self.dateProvider = dateProvider
    }

    /// - Parameters:
    ///   - clipboard: текущий текст буфера (nil/пусто -> отбросить).
    ///   - pasteboardChangeCount: NSPasteboard.changeCount (кумулятивный счётчик копий).
    ///   - precedingText: текст поля до каретки (тот же усечённый префикс, что увидит модель).
    /// - Returns: буфер без изменений если релевантен, иначе nil.
    public func filter(clipboard: String?, pasteboardChangeCount: Int, precedingText: String) -> String? {
        guard let clipboard else { return nil }

        guard let baselineChangeCount = lastKnownChangeCount else {
            // Первое наблюдение: фиксируем baseline (чтобы ловить НОВЫЕ копии), но НЕ заводим
            // часы свежести. Предсуществующий буфер (скопированный до запуска) не подмешиваем,
            // пока юзер реально не скопирует снова при работающем приложении.
            lastKnownChangeCount = pasteboardChangeCount
            return nil
        }

        if pasteboardChangeCount != baselineChangeCount {
            lastKnownChangeCount = pasteboardChangeCount
            lastChangeDate = dateProvider()
        }

        guard let lastChangeDate,
              dateProvider().timeIntervalSince(lastChangeDate) < Self.staleThresholdSeconds
        else {
            return nil
        }

        let clipboardTokens = Self.tokens(from: clipboard)
        let prefixTokens = Self.tokens(from: precedingText)
        guard !clipboardTokens.isDisjoint(with: prefixTokens) else {
            return nil
        }

        return clipboard
    }

    private static func tokens(from text: String) -> Set<String> {
        PromptContextSanitizer.significantTokens(from: text, minimumLength: minimumTokenLength)
    }
}
