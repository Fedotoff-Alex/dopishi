import Testing
@testable import DopishiCore

/// Решения reconciler'а no-flicker (PERF-02): что делать с показанной подсказкой
/// при новом EditingContext - держать, сдвинуть (type-through) или погасить.
@Suite struct SuggestionReconcileTests {

    // MARK: - unchanged: дубль-контекст не гасит ghost (lag-poll/клик в то же место)

    @Test func unchangedPrefixKeepsSuggestion() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "привет, как", newPrefix: "привет, как",
            sameApp: true, shownSuggestion: " дела")
        #expect(d == .unchanged)
    }

    @Test func unchangedPrefixWithoutSuggestionIsUnchanged() {
        // Без подсказки дубль тоже no-op: не перезапускать debounce на poll-тике.
        let d = SuggestionReconcile.decide(
            previousPrefix: "привет", newPrefix: "привет",
            sameApp: true, shownSuggestion: nil)
        #expect(d == .unchanged)
    }

    // MARK: - type-through: набрано начало подсказки

    @Test func typingSuggestionHeadShiftsGhost() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "при", newPrefix: "прив",
            sameApp: true, shownSuggestion: "вет, как дела")
        #expect(d == .typeThrough(remaining: "ет, как дела"))
    }

    @Test func typingWholeSuggestionCompletesIt() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "приве", newPrefix: "привет",
            sameApp: true, shownSuggestion: "т")
        #expect(d == .typedThroughAll)
    }

    @Test func multiCharBurstTypeThrough() {
        // Быстрый набор: AX догнал сразу несколько символов одним контекстом.
        let d = SuggestionReconcile.decide(
            previousPrefix: "к", newPrefix: "кофе",
            sameApp: true, shownSuggestion: "офе и круассан")
        #expect(d == .typeThrough(remaining: " и круассан"))
    }

    @Test func spaceHoldsSuggestionWithoutLeadingSpace() {
        // Стыковая терпимость: подсказка без ведущего пробела ("детали" после "обсудим"),
        // юзер набрал пробел - это тот же стык, НЕ расхождение. Ghost держится как есть.
        let d = SuggestionReconcile.decide(
            previousPrefix: "обсудим", newPrefix: "обсудим ",
            sameApp: true, shownSuggestion: "детали проекта")
        #expect(d == .typeThrough(remaining: "детали проекта"))
    }

    @Test func doubleSpaceStillDiverges() {
        // Второй пробел подряд при подсказке-слове - уже настоящее расхождение.
        let d = SuggestionReconcile.decide(
            previousPrefix: "обсудим ", newPrefix: "обсудим  ",
            sameApp: true, shownSuggestion: "детали")
        #expect(d == .invalidated)
    }

    // MARK: - invalidated: показанная подсказка стала неверной - гасить немедленно

    @Test func divergentTypingInvalidates() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "прив", newPrefix: "привх",
            sameApp: true, shownSuggestion: "ет")
        #expect(d == .invalidated)
    }

    @Test func backspaceInvalidates() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "привет", newPrefix: "приве",
            sameApp: true, shownSuggestion: ", как дела")
        #expect(d == .invalidated)
    }

    @Test func appChangeInvalidatesEvenWithSamePrefix() {
        // SC-2: смена приложения гасит overlay немедленно, даже при совпадении текста.
        let d = SuggestionReconcile.decide(
            previousPrefix: "привет", newPrefix: "привет",
            sameApp: false, shownSuggestion: ", как дела")
        #expect(d == .invalidated)
    }

    @Test func noPreviousContextWithSuggestionInvalidates() {
        let d = SuggestionReconcile.decide(
            previousPrefix: nil, newPrefix: "привет",
            sameApp: true, shownSuggestion: "x")
        #expect(d == .invalidated)
    }

    // MARK: - noSuggestion: подсказки нет - обычный путь (policy + debounce)

    @Test func changedTextWithoutSuggestionIsNoSuggestion() {
        let d = SuggestionReconcile.decide(
            previousPrefix: "прив", newPrefix: "приве",
            sameApp: true, shownSuggestion: nil)
        #expect(d == .noSuggestion)
    }

    @Test func appChangeWithoutSuggestionIsNoSuggestion() {
        // Гасить нечего - но идти обычным путём (cancel тасков + debounce).
        let d = SuggestionReconcile.decide(
            previousPrefix: "привет", newPrefix: "",
            sameApp: false, shownSuggestion: nil)
        #expect(d == .noSuggestion)
    }

    @Test func firstContextEverIsNoSuggestion() {
        let d = SuggestionReconcile.decide(
            previousPrefix: nil, newPrefix: "п",
            sameApp: true, shownSuggestion: nil)
        #expect(d == .noSuggestion)
    }

    @Test func emptySuggestionTreatedAsNoSuggestion() {
        // Пустая строка подсказки эквивалентна её отсутствию.
        let d = SuggestionReconcile.decide(
            previousPrefix: "прив", newPrefix: "приве",
            sameApp: true, shownSuggestion: "")
        #expect(d == .noSuggestion)
    }
}
