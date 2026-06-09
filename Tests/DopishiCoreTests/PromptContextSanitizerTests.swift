import Testing
@testable import DopishiCore

// Поведенческая спецификация PromptContextSanitizer: что считаем prompt-safe и какой OCR-шум
// роняем. Реализация - своя (эвристики по гласным/регистру/длине, без словарей).
@Suite struct PromptContextSanitizerTests {

    // MARK: - sanitize

    @Test func sanitizeStripsANSIEscapeSequences() {
        let input = "\u{001B}[31mERROR\u{001B}[0m something broke"
        let result = PromptContextSanitizer.sanitize(input)
        #expect(!result.contains("\u{001B}"))
        #expect(result.contains("ERROR"))
        #expect(result.contains("something broke"))
    }

    @Test func sanitizeReplacesDisallowedUnicodeWithSpacesPreservingWordBoundaries() {
        #expect(PromptContextSanitizer.sanitize("raw-output") == "raw output")
    }

    @Test func sanitizeCollapsesRepeatedWhitespace() {
        #expect(PromptContextSanitizer.sanitize("hello    world") == "hello world")
    }

    @Test func sanitizeFiltersEmptyAndWhitespaceOnlyLines() {
        #expect(PromptContextSanitizer.sanitize("first\n   \n\nsecond") == "first\nsecond")
    }

    @Test func sanitizeRespectsMaxCharactersLimit() {
        #expect(PromptContextSanitizer.sanitize("abcdefghij", maxCharacters: 5) == "abcde")
    }

    @Test func sanitizeReturnsFullInputWhenMaxCharactersEqualsLength() {
        #expect(PromptContextSanitizer.sanitize("hello", maxCharacters: 5) == "hello")
    }

    @Test func sanitizeReturnsEmptyForWhitespaceOnlyInput() {
        #expect(PromptContextSanitizer.sanitize("   \n  \n  ") == "")
    }

    @Test func sanitizeReturnsEmptyForEmptyInput() {
        #expect(PromptContextSanitizer.sanitize("") == "")
    }

    @Test func sanitizePreservesAllowedCharacters() {
        let input = "Hello world 123 user@host.com"
        #expect(PromptContextSanitizer.sanitize(input) == input)
    }

    @Test func sanitizeHandlesANSIMixedWithRealText() {
        let input = "\u{001B}[32mHello\u{001B}[0m world"
        #expect(PromptContextSanitizer.sanitize(input) == "Hello world")
    }

    // MARK: - sanitizeOCR

    @Test func sanitizeOCRDropsStandaloneNumbers() {
        let result = PromptContextSanitizer.sanitizeOCR("hello 50 world 424")
        #expect(!result.contains("50"))
        #expect(!result.contains("424"))
        #expect(result.contains("hello"))
        #expect(result.contains("world"))
    }

    @Test func sanitizeOCRKeepsVowelTokensDropsConsonantNoise() {
        // "I"/"if"/"like" несут гласную -> держим; "x" без гласной -> шум.
        let result = PromptContextSanitizer.sanitizeOCR("I like if x")
        #expect(result.contains("I"))
        #expect(result.contains("if"))
        #expect(result.contains("like"))
        #expect(!result.contains(" x"))
    }

    @Test func sanitizeOCRDropsLineWhenMajorityTokensAreNoise() {
        // 3 из 4 токенов - шум (>50%): "50", "x", "99" - выживает только "hello", но строка падает.
        #expect(PromptContextSanitizer.sanitizeOCR("50 x 99 hello") == "")
    }

    @Test func sanitizeOCRKeepsLineWhenHalfOrMoreTokensSurvive() {
        // 2 из 4 токенов выживают (ровно 50%): kept.count * 2 >= tokens.count.
        let result = PromptContextSanitizer.sanitizeOCR("hello world 50 99")
        #expect(result.contains("hello"))
        #expect(result.contains("world"))
    }

    @Test func sanitizeOCRRespectsMaxCharacters() {
        let result = PromptContextSanitizer.sanitizeOCR("alpha beta gamma delta epsilon", maxCharacters: 10)
        #expect(result.count <= 10)
    }

    @Test func sanitizeOCRReturnsEmptyForAllNoiseInput() {
        #expect(PromptContextSanitizer.sanitizeOCR("50 424 102 99") == "")
    }

    @Test func sanitizeOCRDropsRandomMixedCaseAndAlphanumericGarbage() {
        let input = """
        gLVWrt bDokE 54tbdbDX
        Visible task update Screen Recording copy for Dopishi
        """
        let result = PromptContextSanitizer.sanitizeOCR(input)
        #expect(!result.contains("gLVWrt"))
        #expect(!result.contains("bDokE"))
        #expect(!result.contains("54tbdbDX"))
        #expect(result.contains("Visible task update Screen Recording copy for Dopishi"))
    }

    @Test func sanitizeOCRPreservesUsefulTechnicalAndUserContext() {
        let input = "Dopishi API context needs GeneralPaneView.swift normalizedBundleIdentifier jane@example.com"
        let result = PromptContextSanitizer.sanitizeOCR(input)
        #expect(result.contains("Dopishi"))                  // слово с гласной
        #expect(result.contains("API"))                      // акроним с гласной
        #expect(result.contains("GeneralPaneView.swift"))    // файл-подобный токен
        #expect(result.contains("normalizedBundleIdentifier")) // длинный camelCase (>12)
        #expect(result.contains("jane@example.com"))         // email
        // NB: двухбуквенный «PR» без гласной отбраковывается как неотличимый от шума -
        // намеренно убран из фикстуры.
    }

    @Test func sanitizeOCRDropsLineWhereMostTokensAreOCRNoise() {
        #expect(PromptContextSanitizer.sanitizeOCR("gLVWrt 54tbdbDX bDokE User") == "")
    }

    @Test func sanitizeOCRPreservesNonLatinScripts() {
        // CJK, кириллица и латиница с диакритикой несут реальный контекст, но без ASCII-гласных и
        // не совпадают со списками англ. слов. Должны переживать OCR-фильтрацию.
        let input = """
        会議の議題を確認してください
        Привет команда смотрите задачу
        Préparez la réunion à Zürich
        """
        let result = PromptContextSanitizer.sanitizeOCR(input)
        #expect(result.contains("会議の議題を確認してください"))
        #expect(result.contains("Привет"))
        #expect(result.contains("задачу"))
        #expect(result.contains("réunion"))
        #expect(result.contains("Zürich"))
    }

    @Test func sanitizeOCRKeepsNonLatinButStillDropsAsciiNoiseOnSameLine() {
        // Не-латинское послабление не должно стать лазейкой для ASCII OCR-мусора на той же строке.
        let result = PromptContextSanitizer.sanitizeOCR("東京 gLVWrt オフィス 54tbdbDX")
        #expect(result.contains("東京"))
        #expect(result.contains("オフィス"))
        #expect(!result.contains("gLVWrt"))
        #expect(!result.contains("54tbdbDX"))
    }

    // MARK: - containsAlphanumericSignal

    @Test func containsAlphanumericSignalTrueForMixedInput() {
        #expect(PromptContextSanitizer.containsAlphanumericSignal("---a---"))
    }

    @Test func containsAlphanumericSignalFalseForPureSymbols() {
        #expect(!PromptContextSanitizer.containsAlphanumericSignal("--- ---"))
    }

    @Test func containsAlphanumericSignalFalseForEmptyString() {
        #expect(!PromptContextSanitizer.containsAlphanumericSignal(""))
    }
}
