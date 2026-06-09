import Testing
@testable import DopishiCore

@Suite struct SuggestionNormalizerTests {
    @Test func stripsControlTokens() {
        #expect(SuggestionNormalizer.normalize("<|im_start|>привет") == "привет")
        #expect(SuggestionNormalizer.normalize("текст<|endoftext|>") == "текст")
    }
    @Test func stripsGemmaTurnTokens() {
        #expect(SuggestionNormalizer.normalize("<end_of_turn>") == "")
        #expect(SuggestionNormalizer.normalize("<start_of_turn>model привет") == " привет")
    }
    @Test func stripsThinkBlock() {
        #expect(SuggestionNormalizer.normalize("<think>рассуждение</think>ответ") == "ответ")
    }
    @Test func stripsScaffoldingLabel() {
        #expect(SuggestionNormalizer.normalize("Task: продолжение") == "продолжение")
        #expect(SuggestionNormalizer.normalize("Continuation: мир") == "мир")
    }
    @Test func keepsPlainText() {
        #expect(SuggestionNormalizer.normalize("обычный текст") == "обычный текст")
        #expect(SuggestionNormalizer.normalize(" мир дом") == " мир дом")
    }
    @Test func keepsLeadingSpaceOnPlain() {
        // ведущий пробел важен для стыка - не трогаем, если нет артефактов
        #expect(SuggestionNormalizer.normalize(" привет") == " привет")
    }
    @Test func empty() {
        #expect(SuggestionNormalizer.normalize("") == "")
    }
    @Test func normalizesWhitespace() {
        // неразрывный пробел -> обычный (иначе firstChunk не разделит слова по Tab)
        #expect(SuggestionNormalizer.normalize("слово\u{00A0}слово") == "слово слово")
        // двойные пробелы -> один
        #expect(SuggestionNormalizer.normalize("слово  слово") == "слово слово")
        // ведущий пробел сохраняется (схлопнут до одного)
        #expect(SuggestionNormalizer.normalize("  мир") == " мир")
        // одинарные пробелы не трогаем
        #expect(SuggestionNormalizer.normalize(" мир дом") == " мир дом")
    }
}
