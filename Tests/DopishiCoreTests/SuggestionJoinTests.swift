import Testing
@testable import DopishiCore

@Suite struct SuggestionJoinTests {
    @Test func stripsLeadingSpaceWhenContextEndsWithSpace() {
        #expect(SuggestionJoin.normalize(" мир", after: "привет ") == "мир")
    }
    @Test func stripsAllLeadingSpaces() {
        #expect(SuggestionJoin.normalize("   мир", after: "привет ") == "мир")
    }
    @Test func keepsLeadingSpaceWhenContextHasNoTrailingSpace() {
        #expect(SuggestionJoin.normalize(" мир", after: "привет") == " мир")
    }
    @Test func noChangeWhenSuggestionHasNoLeadingSpace() {
        #expect(SuggestionJoin.normalize("мир", after: "привет ") == "мир")
    }
    @Test func emptySuggestion() {
        #expect(SuggestionJoin.normalize("", after: "привет ") == "")
    }
    @Test func emptyContextKeepsSuggestion() {
        #expect(SuggestionJoin.normalize(" мир", after: "") == " мир")
    }
    @Test func stripsLeadingSpaceWhenMidWord() {
        // Дописываем незаконченное слово - ведущий пробел был бы ВНУТРИ слова.
        #expect(SuggestionJoin.normalize(" д", after: "велосипе", midWord: true) == "д")
        #expect(SuggestionJoin.normalize("  ить", after: "поступ", midWord: true) == "ить")
    }
    @Test func keepsLeadingSpaceForCompleteWordWithoutMidWord() {
        // Законченное слово без хвостового пробела (midWord=false) - разделитель нужен.
        #expect(SuggestionJoin.normalize(" мир", after: "привет", midWord: false) == " мир")
    }

    // MARK: - добавление недостающего пробела на стыке (модель начала слово без пробела)

    @Test func addsJointSpaceBetweenWords() {
        // Некоторые модели (YandexGPT) продолжают новым словом БЕЗ ведущего пробела:
        // без вставки разделителя ghost клеится к слову, а набранный пробел убивает
        // подсказку (посимвольное расхождение в reconciler).
        #expect(SuggestionJoin.normalize("мир", after: "привет") == " мир")
        #expect(SuggestionJoin.normalize("детали проекта", after: "обсудим") == " детали проекта")
    }

    @Test func noJointSpaceWhenMidWord() {
        // Дописывание незаконченного слова - клеим без пробела, как раньше.
        #expect(SuggestionJoin.normalize("д", after: "велосипе", midWord: true) == "д")
    }

    @Test func noJointSpaceForPunctuation() {
        // Продолжение пунктуацией - законная склейка без пробела.
        #expect(SuggestionJoin.normalize(", мир", after: "привет") == ", мир")
        #expect(SuggestionJoin.normalize("!", after: "привет") == "!")
    }

    @Test func noJointSpaceWhenContextEndsWithBoundary() {
        #expect(SuggestionJoin.normalize("мир", after: "привет ") == "мир")
        #expect(SuggestionJoin.normalize("мир", after: "привет,") == "мир")
    }
}

@Suite struct SuggestionJoinCompletesFragmentTests {
    // Мини-словарь вместо NSSpellChecker (он в App-таргете, Core-тестам недоступен).
    private static let dict: Set<String> = [
        "при", "на", "она", "мир", "привет", "приложение", "велосипед", "кофе", "кофейня", "от",
    ]
    private func valid(_ w: String) -> Bool { Self.dict.contains(w.lowercased()) }

    @Test func joinsWhenFragmentIsValidWordAndGlueIsWord() {
        // Баг "при ложение": фрагмент "при" - словарный, эвристика misspelled-mid-word
        // промахивается. Стык: "ложение" само не словарное, "приложение" - словарное -> склейка.
        #expect(SuggestionJoin.completesFragment(" ложение", after: "запустил при", isValidWord: valid))
    }
    @Test func joinsMultiWordSuggestionByFirstWord() {
        #expect(SuggestionJoin.completesFragment(" йня на углу", after: "кофе", isValidWord: valid))
    }
    @Test func keepsSpaceWhenSuggestionFirstWordIsValidItself() {
        // "о" + " на": "на" - валидное слово, значит модель начинает НОВОЕ слово ("она" не склеиваем).
        #expect(!SuggestionJoin.completesFragment(" на", after: "я думал о", isValidWord: valid))
    }
    @Test func keepsSpaceWhenGlueIsNotAWord() {
        #expect(!SuggestionJoin.completesFragment(" ыыы", after: "привет", isValidWord: valid))
    }
    @Test func noJoinWhenContextEndsWithBoundary() {
        #expect(!SuggestionJoin.completesFragment(" ложение", after: "при ", isValidWord: valid))
        #expect(!SuggestionJoin.completesFragment(" ложение", after: "при,", isValidWord: valid))
    }
    @Test func noJoinWithoutLeadingSpace() {
        // Без ведущего пробела стык и так корректен - normalize ничего не трогает.
        #expect(!SuggestionJoin.completesFragment("ложение", after: "при", isValidWord: valid))
    }
    @Test func noJoinOnEmptyInputs() {
        #expect(!SuggestionJoin.completesFragment("", after: "при", isValidWord: valid))
        #expect(!SuggestionJoin.completesFragment(" ", after: "при", isValidWord: valid))
        #expect(!SuggestionJoin.completesFragment(" ложение", after: "", isValidWord: valid))
    }
}
