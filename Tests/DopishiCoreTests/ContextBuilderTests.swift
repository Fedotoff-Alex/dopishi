import Testing
import Foundation
@testable import DopishiCore

@Suite struct ContextBuilderTests {
    private func ocr(_ text: String) -> OCRContext {
        OCRContext(windowText: text, capturedAt: Date(timeIntervalSince1970: 0), windowId: 1)
    }

    @Test func noOcrPathEqualsFewShotCompletionPrompt() {
        let b = ContextBundle(fieldTail: "Я хочу пойти ", ocr: nil)
        #expect(ContextBuilder.build(b) == PromptBuilder.fewShotCompletionPrompt(from: "Я хочу пойти "))
    }

    @Test func emptyOcrFallsBackToNoOcrPath() {
        let b = ContextBundle(fieldTail: "привет", ocr: ocr(""))
        #expect(ContextBuilder.build(b) == PromptBuilder.fewShotCompletionPrompt(from: "привет"))
    }

    @Test func ocrPathPreservesStaticHeadForKVReuse() {
        let b = ContextBundle(fieldTail: "привет", ocr: ocr("Тема: отпуск"))
        let p = ContextBuilder.build(b)
        // KV-инвариант: голова промпта - литеральный статический префикс (без финального "Текст:").
        #expect(p.hasPrefix(PromptBuilder.fewShotPrefixWithoutLastTextLabel))
        #expect(p.contains("Окно: Тема: отпуск"))
        #expect(p.contains("Текст: привет"))
        #expect(p.hasSuffix("\nПродолжение:"))
    }

    @Test func ocrSectionGoesBeforeTextLabel() {
        let b = ContextBundle(fieldTail: "тело", ocr: ocr("заголовок"))
        let p = ContextBuilder.build(b)
        let okno = p.range(of: "Окно: заголовок")!
        let text = p.range(of: "Текст: тело")!
        #expect(okno.lowerBound < text.lowerBound)   // "Окно:" перед "Текст:"
    }

    @Test func ocrTextCollapsedAndTruncated() {
        let long = String(repeating: "ab\n", count: 200)   // 600 симв с переводами строк
        let b = ContextBundle(fieldTail: "x", ocr: ocr(long))
        let p = ContextBuilder.build(b, ocrMax: 20)
        // Секция Окно: между "Окно: " и "\nТекст:" - без переводов строк и не больше ocrMax.
        let win = p.components(separatedBy: "Окно: ")[1].components(separatedBy: "\nТекст:")[0]
        #expect(!win.contains("\n"))
        #expect(win.count <= 20)
    }

    @Test func tailTrimmedToBudgetFromEnd() {
        let long = String(repeating: "a", count: 50) + "ХВОСТ"
        let b = ContextBundle(fieldTail: long, ocr: ocr("окно"))
        let p = ContextBuilder.build(b, tailMax: 5)
        #expect(p.contains("Текст: ХВОСТ"))
        #expect(!p.contains("aaaa"))
    }

    // --- clipboard-канал (фаза 2) ---
    @Test func clipboardOnlyPathPreservesStaticHead() {
        let b = ContextBundle(fieldTail: "привет", ocr: nil, clipboard: "адрес: Павловская 27")
        let p = ContextBuilder.build(b)
        #expect(p.hasPrefix(PromptBuilder.fewShotPrefixWithoutLastTextLabel))
        #expect(p.contains("Буфер: адрес: Павловская 27"))
        #expect(p.contains("Текст: привет"))
        #expect(!p.contains("Окно:"))
        #expect(p.hasSuffix("\nПродолжение:"))
    }

    @Test func ocrAndClipboardBothBeforeTextInOrder() {
        let b = ContextBundle(fieldTail: "тело", ocr: ocr("заголовок"), clipboard: "буфер текст")
        let p = ContextBuilder.build(b)
        let okno = p.range(of: "Окно: заголовок")!
        let bufer = p.range(of: "Буфер: буфер текст")!
        let text = p.range(of: "Текст: тело")!
        #expect(okno.lowerBound < bufer.lowerBound)   // Окно перед Буфером
        #expect(bufer.lowerBound < text.lowerBound)   // Буфер перед Текстом
    }

    @Test func nilClipboardByDefaultIsNoChannel() {
        // clipboard по умолчанию nil -> ровно как путь без каналов (нулевая регрессия).
        let b = ContextBundle(fieldTail: "Я хочу пойти ")
        #expect(ContextBuilder.build(b) == PromptBuilder.fewShotCompletionPrompt(from: "Я хочу пойти "))
    }

    @Test func clipboardCollapsedAndTruncated() {
        let long = String(repeating: "cd\n", count: 200)
        let b = ContextBundle(fieldTail: "x", ocr: nil, clipboard: long)
        let p = ContextBuilder.build(b, clipMax: 15)
        let clip = p.components(separatedBy: "Буфер: ")[1].components(separatedBy: "\nТекст:")[0]
        #expect(!clip.contains("\n"))
        #expect(clip.count <= 15)
    }

    // --- memory-канал (фаза 3) ---
    @Test func memoryOnlyPathPreservesStaticHead() {
        let b = ContextBundle(fieldTail: "привет", ocr: nil, clipboard: nil, memory: "вчера обсуждали смету")
        let p = ContextBuilder.build(b)
        #expect(p.hasPrefix(PromptBuilder.fewShotPrefixWithoutLastTextLabel))
        #expect(p.contains("Память: вчера обсуждали смету"))
        #expect(p.contains("Текст: привет"))
        #expect(!p.contains("Окно:"))
        #expect(!p.contains("Буфер:"))
        #expect(p.hasSuffix("\nПродолжение:"))
    }

    @Test func allChannelsOrderMemoryWindowClipboardThenText() {
        let b = ContextBundle(fieldTail: "тело", ocr: ocr("заголовок"),
                              clipboard: "буфер текст", memory: "история диалога")
        let p = ContextBuilder.build(b)
        let mem = p.range(of: "Память: история диалога")!
        let okno = p.range(of: "Окно: заголовок")!
        let bufer = p.range(of: "Буфер: буфер текст")!
        let text = p.range(of: "Текст: тело")!
        #expect(mem.lowerBound < okno.lowerBound)
        #expect(okno.lowerBound < bufer.lowerBound)
        #expect(bufer.lowerBound < text.lowerBound)
    }

    @Test func nilMemoryByDefaultIsNoChannel() {
        let b = ContextBundle(fieldTail: "Я хочу пойти ")
        #expect(ContextBuilder.build(b) == PromptBuilder.fewShotCompletionPrompt(from: "Я хочу пойти "))
    }
}
