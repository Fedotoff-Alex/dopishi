import Testing
@testable import DopishiCore

@Suite struct WordToolsTests {
    @Test func boundaries() {
        #expect(WordBoundary.isBoundary(" "))
        #expect(WordBoundary.isBoundary("\n"))
        #expect(WordBoundary.isBoundary(","))
        #expect(!WordBoundary.isBoundary("a"))
        #expect(!WordBoundary.isBoundary("я"))
        #expect(!WordBoundary.isBoundary("-"))
    }
    @Test func lastWord() {
        #expect(WordEdit.lastWord(of: "привет мир") == "мир")
        #expect(WordEdit.lastWord(of: "привет мир ") == "мир")
        #expect(WordEdit.lastWord(of: "ghbdtn") == "ghbdtn")
        #expect(WordEdit.lastWord(of: "") == "")
        #expect(WordEdit.lastWord(of: "   ") == "")
    }
    @Test func layoutDecision() {
        #expect(LayoutDecision.shouldSwitch(asTypedIsWord: false, transliteratedIsWord: true))
        #expect(!LayoutDecision.shouldSwitch(asTypedIsWord: true, transliteratedIsWord: true))
        #expect(!LayoutDecision.shouldSwitch(asTypedIsWord: false, transliteratedIsWord: false))
    }

    // Баг из живого UAT: предлоги/короткие слова не конвертятся EN->RU. Причины:
    // (A) 1 буква; (B) латиница - "валидное" англ. слово (vs/pf/bp) -> asTypedIsWord=true.
    // Контекстное решение: язык соседнего текста задаёт намерение.
    @Test func layoutDecisionWithContext() {
        // Контекст русский, цель русская: конвертим даже если латиница "валидна" по-en (vs="versus")
        // или это 1 буква - лишь бы транслит был словарным.
        #expect(LayoutDecision.shouldSwitch(asTypedIsWord: true, transliteratedIsWord: true,
                                            contextScript: .cyrillic, targetScript: .cyrillic))
        #expect(LayoutDecision.shouldSwitch(asTypedIsWord: false, transliteratedIsWord: true,
                                            contextScript: .cyrillic, targetScript: .cyrillic))
        // Контекст английский: НЕ конвертим в русский (пишем по-английски, "vs" остаётся).
        #expect(!LayoutDecision.shouldSwitch(asTypedIsWord: true, transliteratedIsWord: true,
                                             contextScript: .latin, targetScript: .cyrillic))
        // Транслит - мусор (не словарь): не свитчим даже в русском контексте.
        #expect(!LayoutDecision.shouldSwitch(asTypedIsWord: false, transliteratedIsWord: false,
                                             contextScript: .cyrillic, targetScript: .cyrillic))
        // Нет контекста (начало строки) - падаем на словарную эвристику.
        #expect(LayoutDecision.shouldSwitch(asTypedIsWord: false, transliteratedIsWord: true,
                                            contextScript: .neutral, targetScript: .cyrillic))
        #expect(!LayoutDecision.shouldSwitch(asTypedIsWord: true, transliteratedIsWord: true,
                                             contextScript: .neutral, targetScript: .cyrillic))
    }
    @Test func lastSpaceToken() {
        // пунктуация внутри токена сохраняется (не делим по запятой)
        #expect(WordEdit.lastSpaceToken(of: "ghbdtn,vbh") == "ghbdtn,vbh")
        #expect(WordEdit.lastSpaceToken(of: "привет ghbdtn,vbh") == "ghbdtn,vbh")
        #expect(WordEdit.lastSpaceToken(of: "слово") == "слово")
        #expect(WordEdit.lastSpaceToken(of: "ghbdtn ") == "")
        #expect(WordEdit.lastSpaceToken(of: "") == "")
    }
    @Test func lastSpaceTokenWithTrailing() {
        // ключевой кейс: пробел уже стоит - токен берём, пробел сохраняем как trailing
        var r = WordEdit.lastSpaceTokenWithTrailing(of: "ghbdtn ")
        #expect(r.token == "ghbdtn"); #expect(r.trailing == " ")
        // без хвостового пробела - как обычный токен, trailing пуст
        r = WordEdit.lastSpaceTokenWithTrailing(of: "ghbdtn")
        #expect(r.token == "ghbdtn"); #expect(r.trailing == "")
        // несколько пробелов сохраняем целиком
        r = WordEdit.lastSpaceTokenWithTrailing(of: "привет ghbdtn  ")
        #expect(r.token == "ghbdtn"); #expect(r.trailing == "  ")
        // пунктуация внутри токена остаётся (как у lastSpaceToken)
        r = WordEdit.lastSpaceTokenWithTrailing(of: "ghbdtn,vbh ")
        #expect(r.token == "ghbdtn,vbh"); #expect(r.trailing == " ")
        // перенос строки в trailing НЕ собираем -> токена нет (слово на прошлой строке)
        r = WordEdit.lastSpaceTokenWithTrailing(of: "ghbdtn\n")
        #expect(r.token == ""); #expect(r.trailing == "")
        // таб тоже считается хвостовым
        r = WordEdit.lastSpaceTokenWithTrailing(of: "ghbdtn\t")
        #expect(r.token == "ghbdtn"); #expect(r.trailing == "\t")
        // пусто
        r = WordEdit.lastSpaceTokenWithTrailing(of: "")
        #expect(r.token == ""); #expect(r.trailing == "")
    }
}
