import Testing
@testable import DopishiCore

@Suite struct EchoPrefixGuardTests {
    // Базовые случаи из задания
    @Test func stripsEchoWord() {
        // "написал" - эхо последнего слова контекста
        #expect(EchoPrefixGuard.strip("написал письмо", context: "я написал") == "письмо")
    }
    @Test func stripsEchoWordPreservingLeadingSpace() {
        // ведущий пробел должен сохраниться после среза
        #expect(EchoPrefixGuard.strip(" написал письмо", context: "я написал") == " письмо")
    }
    @Test func noEchoKeepsAsIs() {
        // нет совпадения - возвращаем без изменений
        #expect(EchoPrefixGuard.strip("письмо другу", context: "я написал") == "письмо другу")
    }
    @Test func noEchoWithLeadingSpace() {
        #expect(EchoPrefixGuard.strip(" мир", context: "привет") == " мир")
    }
    @Test func emptyStaysEmpty() {
        #expect(EchoPrefixGuard.strip("", context: "привет") == "")
    }

    // Дополнительные случаи
    @Test func stripsMultiWordEcho() {
        // два слова эха: "я написал" совпадает с хвостом контекста "до этого я написал"
        #expect(EchoPrefixGuard.strip("я написал письмо", context: "до этого я написал") == "письмо")
    }
    @Test func caseInsensitiveEcho() {
        // folded-сравнение ловит разный регистр
        #expect(EchoPrefixGuard.strip("Написал письмо", context: "я написал") == "письмо")
    }
    @Test func pureEchoReturnsLeadingSpaceOrEmpty() {
        // только эхо, больше ничего - возвращаем leadingSpace (может быть пустым)
        #expect(EchoPrefixGuard.strip("написал", context: "я написал") == "")
        #expect(EchoPrefixGuard.strip(" написал", context: "я написал") == " ")
    }
    @Test func emptyContextNoChange() {
        #expect(EchoPrefixGuard.strip("письмо", context: "") == "письмо")
    }
    @Test func longContextTailLimitedToSix() {
        // контекст длинный - максимум 6 слов из хвоста
        let ctx = "а б в г д е ж з и к"
        // подсказка начинается ровно с 6 последних слов контекста ("д е ж з и к")
        let sug = "д е ж з и к продолжение"
        let result = EchoPrefixGuard.strip(sug, context: ctx)
        // 6 слов эха срезано, остаётся только "продолжение"
        #expect(result == "продолжение")
    }
}
