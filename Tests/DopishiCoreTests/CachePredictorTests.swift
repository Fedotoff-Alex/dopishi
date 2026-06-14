import Testing
@testable import DopishiCore

@Suite struct CachePredictorTests {
    @Test func predictsRepeatedContinuation() {
        var p = CachePredictor()
        p.learn("добрый день, коллеги")
        p.learn("добрый день, друзья! добрый день")
        // "добрый" -> "день" встречается 3 раза - уверенно.
        #expect(p.predict(after: "всем добрый ")?.hasPrefix(" день") == true)
    }
    @Test func silentOnSingleObservation() {
        var p = CachePredictor()
        p.learn("уникальная пара слов")
        #expect(p.predict(after: "уникальная ") == nil)   // minCount 2
    }
    @Test func silentWithoutMajority() {
        var p = CachePredictor()
        p.learn("пишем код. пишем тесты. пишем код. пишем доки. пишем код")
        // "пишем" -> код 3/5 = 60% - на грани, проходит.
        #expect(p.predict(after: "мы пишем ")?.hasPrefix(" код") == true)
        p.learn("пишем тесты. пишем доки")
        // теперь код 3/7 < 60% - молчим.
        #expect(p.predict(after: "мы пишем ") == nil)
    }
    @Test func chainsConfidentWords() {
        var p = CachePredictor()
        p.learn("с уважением Алекс")
        p.learn("с уважением Алекс")
        let out = p.predict(after: "подпись: с ")
        #expect(out == " уважением Алекс")
    }
    @Test func emptyIndexSilent() {
        let p = CachePredictor()
        #expect(p.predict(after: "что угодно ") == nil)
    }
}

@Suite struct PromptBudgetTests {
    @Test func midWordIsShort() {
        #expect(PromptBudget.tailMax(prefix: "пишу велосипе", isMidWord: true) == 240)
    }
    @Test func sentenceEndIsFull() {
        #expect(PromptBudget.tailMax(prefix: "мысль закончена.", isMidWord: false) == 600)
        #expect(PromptBudget.tailMax(prefix: "строка\n", isMidWord: false) == 600)
    }
    @Test func midSentenceIsMedium() {
        #expect(PromptBudget.tailMax(prefix: "пишем дальше и", isMidWord: false) == 400)
    }
}
