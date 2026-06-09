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
