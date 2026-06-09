import Testing
import Foundation
@testable import DopishiMemory

@Suite struct MemoryRetrievalTests {
    private func item(_ text: String, _ ts: TimeInterval) -> MemoryItem {
        MemoryItem(threadKey: "t", kind: .message, text: text, createdAt: Date(timeIntervalSince1970: ts))
    }

    @Test func emptyReturnsEmpty() {
        #expect(MemoryRetrieval.format([]) == "")
    }

    @Test func newestFirstInputProducesChronological() {
        // вход новейшие-первыми (как из recentItems) -> выход старое->новое
        let items = [item("третье", 30), item("второе", 20), item("первое", 10)]
        #expect(MemoryRetrieval.format(items) == "первое второе третье")
    }

    @Test func budgetKeepsNewestWithinLimit() {
        let items = [item("ccc", 30), item("bbb", 20), item("aaa", 10)]   // новейшие первыми
        // "ccc"(3)+1=4 <=7; +"bbb" -> 8 >7 -> только новейший
        #expect(MemoryRetrieval.format(items, maxChars: 7) == "ccc")
    }

    @Test func sanitizesText() {
        #expect(MemoryRetrieval.format([item("raw-data", 10)]) == "raw data")
    }

    @Test func skipsEmptyAfterSanitize() {
        let items = [item("реальный текст", 20), item(">>> ===", 10)]
        #expect(MemoryRetrieval.format(items) == "реальный текст")
    }

    @Test func oversizedNewestItemTruncatedNotDropped() {
        // Новейший элемент один длиннее бюджета: раньше break давал пустой канал. Теперь - голова.
        let long = String(repeating: "a", count: 50)
        let r = MemoryRetrieval.format([item(long, 30), item("старое", 10)], maxChars: 20)
        #expect(!r.isEmpty)
        #expect(r.count <= 20)
        #expect(r.hasPrefix("a"))
    }
}
