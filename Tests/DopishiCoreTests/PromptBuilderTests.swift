import Testing
@testable import DopishiCore

@Suite struct PromptBuilderTests {
    @Test func returnsTextWhenShort() {
        #expect(PromptBuilder.completionPrompt(from: "Привет, мир", maxChars: 100) == "Привет, мир")
    }
    @Test func keepsTailWhenTooLong() {
        let long = String(repeating: "a", count: 50) + "ХВОСТ"
        let p = PromptBuilder.completionPrompt(from: long, maxChars: 5)
        #expect(p == "ХВОСТ")
    }
    @Test func emptyStaysEmpty() {
        #expect(PromptBuilder.completionPrompt(from: "", maxChars: 100) == "")
    }
    @Test func trimsTrailingWhitespace() {
        // Прямой прогон движка: с trailing-пробелом подсказки портятся ("2-й язык"),
        // без него - осмысленны ("русский язык"). Поэтому обрезаем.
        #expect(PromptBuilder.completionPrompt(from: "привет мир ", maxChars: 100) == "привет мир")
        #expect(PromptBuilder.completionPrompt(from: "слово\n", maxChars: 100) == "слово")
        #expect(PromptBuilder.completionPrompt(from: "слово\t", maxChars: 100) == "слово")
    }
    @Test func chatPromptWrapsTextInGemmaTurns() {
        let p = PromptBuilder.chatPrompt(from: "Привет мир", maxChars: 100)
        #expect(p.contains("<start_of_turn>user"))
        #expect(p.contains("Привет мир"))
        #expect(p.hasSuffix("<start_of_turn>model\n"))
    }

    @Test func autocompletePromptUsesGemmaFormatForGemmaModels() {
        let p = PromptBuilder.autocompletePrompt(
            from: "Привет, как дела ",
            modelFileName: "gemma-4-E2B-i1-Q4_K_M.gguf",
            maxChars: 100
        )
        #expect(p.contains("<start_of_turn>user"))
        #expect(p.contains("Return ONLY the exact text to insert after the cursor."))
        #expect(p.contains("in Russian"))
        #expect(p.hasSuffix("<start_of_turn>model"))
    }

    @Test func autocompletePromptKeepsPlainForNonGemmaModels() {
        let p = PromptBuilder.autocompletePrompt(
            from: "Привет мир ",
            modelFileName: "Qwen3.5-4B-Q4_K_M.gguf",
            maxChars: 100
        )
        #expect(p == "Привет мир")  // plain-путь обрезает trailing-пробел
    }

    @Test func fewShotPromptWrapsContextWithStaticPrefix() {
        let p = PromptBuilder.fewShotCompletionPrompt(from: "Я хочу пойти ", maxChars: 100)
        // Статический few-shot префикс присутствует целиком (важно для KV prefix-reuse).
        #expect(p.hasPrefix(PromptBuilder.fewShotPrefix))
        // Контекст с обрезанным trailing-пробелом и маркер генерации в конце.
        #expect(p.contains("Я хочу пойти"))
        #expect(!p.contains("пойти  "))
        #expect(p.hasSuffix("\nПродолжение:"))
    }

    @Test func fewShotPromptKeepsTailWhenTooLong() {
        let long = String(repeating: "a", count: 50) + "ХВОСТ"
        let p = PromptBuilder.fewShotCompletionPrompt(from: long, maxChars: 5)
        #expect(p.contains("ХВОСТ"))
        #expect(!p.contains("aaaa"))
    }

    @Test func plainRawPreservesTrailingWhitespace() {
        // Бриф просил проверить вариант С trailing-пробелом - plainRaw его сохраняет.
        #expect(PromptBuilder.plainRawPrompt(from: "привет мир ", maxChars: 100) == "привет мир ")
    }

    @Test func minimalInlineWrapsAndTrims() {
        let p = PromptBuilder.minimalInlinePrompt(from: "привет мир ", maxChars: 100)
        #expect(p == "Продолжи текст коротко тем же языком: привет мир")
    }

    @Test func fewShotPrefixWithoutLabelPlusTextLabelEqualsPrefix() {
        // KV-инвариант: голова без "Текст:" + "Текст:" == исходный few-shot префикс.
        #expect(PromptBuilder.fewShotPrefixWithoutLastTextLabel + "Текст:" == PromptBuilder.fewShotPrefix)
        #expect(!PromptBuilder.fewShotPrefixWithoutLastTextLabel.hasSuffix("Текст:"))
    }

    @Test func modeDispatchMatchesDirectBuilders() {
        let ctx = "Я хочу пойти "
        #expect(PromptBuilder.build(mode: .fewShot, from: ctx) == PromptBuilder.fewShotCompletionPrompt(from: ctx))
        #expect(PromptBuilder.build(mode: .plainTrimmed, from: ctx) == PromptBuilder.completionPrompt(from: ctx))
        #expect(PromptBuilder.build(mode: .plainRaw, from: ctx) == PromptBuilder.plainRawPrompt(from: ctx))
        #expect(PromptBuilder.build(mode: .minimalInline, from: ctx) == PromptBuilder.minimalInlinePrompt(from: ctx))
    }
}
