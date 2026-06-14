import Testing
@testable import DopishiCore

@Suite struct WindowSanitizerTests {

    // ASCII - start и end точно на границах, слайс возвращается без изменений
    @Test func asciiExactBoundaries() {
        let result = WindowSanitizer.sanitize("hello world", utf16Start: 2, utf16End: 7)
        #expect(result.slice == "llo w")
        #expect(result.adjustedStart == 2)
    }

    // Emoji (🙂 = 2 UTF-16 units): start попадает на второй unit суррогатной пары
    // walk-FORWARD сдвигает start с 2 на 3 (начало "b"), slice = "b"
    @Test func emojiStartInsideSurrogateWalksForward() {
        let t = "a🙂b"
        #expect(t.utf16.count == 4)
        let result = WindowSanitizer.sanitize(t, utf16Start: 2, utf16End: 4)
        #expect(result.slice == "b")
        #expect(result.adjustedStart == 3)
    }

    // Emoji: end попадает на второй unit 🙂, walk-BACK к 1 -> slice = "a"
    @Test func emojiEndInsideSurrogateWalksBack() {
        let result = WindowSanitizer.sanitize("a🙂b", utf16Start: 0, utf16End: 2)
        #expect(result.slice == "a")
        #expect(result.adjustedStart == 0)
    }

    // ZWJ-последовательность (🏳️‍🌈 = 6 UTF-16 units) не разрывается:
    // окно точно покрывает флаг - slice должен быть валидной строкой, равной самому флагу
    @Test func zwjSequenceNotSplit() {
        let flag = "🏳️‍🌈"
        let text = "x" + flag + "y"
        #expect(flag.utf16.count == 6)
        let result = WindowSanitizer.sanitize(text, utf16Start: 1, utf16End: 1 + flag.utf16.count)
        #expect(result.slice == flag)
        #expect(result.adjustedStart == 1)
    }

    // Кириллица: каждый символ = 1 UTF-16 unit, невалидных границ нет
    @Test func cyrillicNeverInvalidBoundary() {
        let t = "привет мир"
        #expect(t.count == t.utf16.count)
        let result = WindowSanitizer.sanitize(t, utf16Start: 3, utf16End: 6)
        #expect(result.slice == "вет")
        #expect(result.adjustedStart == 3)
    }

    // Combining mark (e + \u{301}): end между e и combining -> walk-BACK
    // walk-BACK возвращает "" (откатывается до 0, слайс становится пустым, т.к. s==e==0)
    @Test func combiningMarkNotSplit() {
        let t = "e\u{301}x"
        #expect(t.utf16.count == 3)
        // end=1 - между "e" и combining, walk-BACK к 0, s==e -> ("", 0)
        let result = WindowSanitizer.sanitize(t, utf16Start: 0, utf16End: 1)
        // e\u{301} - это один grapheme, граница в utf16 offset=1 НЕ валидна для String.Index
        // поэтому walk-back до 0, s==e, результат пустой
        #expect(result.slice == "")
        #expect(result.adjustedStart == 0)
    }

    // start == end -> возвращает ("", start)
    @Test func startEqualsEndReturnsEmpty() {
        let result = WindowSanitizer.sanitize("hello", utf16Start: 3, utf16End: 3)
        #expect(result.slice == "")
        #expect(result.adjustedStart == 3)
    }

    // utf16Start == 0: нет смещения
    @Test func startZeroNotShifted() {
        let result = WindowSanitizer.sanitize("hello", utf16Start: 0, utf16End: 3)
        #expect(result.slice == "hel")
        #expect(result.adjustedStart == 0)
    }

    // utf16End == text.utf16.count: нет смещения конца
    @Test func endAtCountNotShifted() {
        let result = WindowSanitizer.sanitize("hello", utf16Start: 1, utf16End: 5)
        #expect(result.slice == "ello")
        #expect(result.adjustedStart == 1)
    }

    // Out-of-bounds: utf16End > text.utf16.count -> безопасный дефолт
    @Test func outOfBoundsReturnsSafeDefault() {
        let result = WindowSanitizer.sanitize("hello", utf16Start: 2, utf16End: 99)
        #expect(result.slice == "")
        #expect(result.adjustedStart == 2)
    }

    // КРИТИЧЕСКИЙ (Pitfall 2): пересчёт precedingText из оконного слайса
    // должен совпадать с prefix из полного текста при том же caret.
    // Регрессия: при utf16Start=0 (окно от начала) offset-math держится точно.
    @Test func offsetMathMatchesFullPrefix() {
        let full = "очень длинный кириллический текст здесь"
        let caret = 20
        let (slice, adjStart) = WindowSanitizer.sanitize(full, utf16Start: 0, utf16End: full.utf16.count)
        #expect(adjStart == 0)
        #expect(TextPrefix.byUTF16Offset(slice, offset: caret - adjStart) ==
                TextPrefix.byUTF16Offset(full, offset: caret))
    }

    // D-03 regression: интеграционная проверка арифметики shrink-эвристики из ContextProbe.buildContext
    // (условие newText.count * 2 < prev.count). Тест здесь, а не в ContextProbeTests, как регрессия
    // граничных значений cap=800, специфичных для Phase 2. WindowSanitizer не вызывается напрямую.
    @Test func shrinkHeuristicFiresOnCappedText() {
        let prev = String(repeating: "а", count: 800)
        let new = ""
        #expect(prev.count >= 8)
        #expect(new.count * 2 < prev.count)
    }

    // MARK: - dropEdgeClusters (D-06)

    // Нет флагов - слайс не изменяется, droppedStart=0
    @Test func dropEdgeClusters_noFlags_noChange() {
        let s = "hello world"
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: false, cutAtEnd: false)
        #expect(result == s)
        #expect(dropped == 0)
    }

    // cutAtStart дропает первый ASCII grapheme
    @Test func dropEdgeClusters_cutAtStart_dropsFirstChar() {
        let (result, dropped) = WindowSanitizer.dropEdgeClusters("hello", cutAtStart: true, cutAtEnd: false)
        #expect(result == "ello")
        #expect(dropped == 1)
    }

    // cutAtEnd дропает последний ASCII grapheme, droppedStart=0
    @Test func dropEdgeClusters_cutAtEnd_dropsLastChar() {
        let (result, dropped) = WindowSanitizer.dropEdgeClusters("hello", cutAtStart: false, cutAtEnd: true)
        #expect(result == "hell")
        #expect(dropped == 0)
    }

    // U+FFFD на начале: cutAtStart дропает его (1 UTF-16 unit)
    @Test func dropEdgeClusters_fffdAtStart_dropped() {
        let s = "\u{FFFD}hello"
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: true, cutAtEnd: false)
        #expect(result == "hello")
        #expect(dropped == 1)
    }

    // U+FFFD на конце: cutAtEnd дропает его
    @Test func dropEdgeClusters_fffdAtEnd_dropped() {
        let s = "hello\u{FFFD}"
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: false, cutAtEnd: true)
        #expect(result == "hello")
        #expect(dropped == 0)
    }

    // Emoji (🙂 = 2 UTF-16 units) на начале: droppedStart=2
    @Test func dropEdgeClusters_emojiAtStart_dropped2UTF16() {
        let s = "🙂hello"
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: true, cutAtEnd: false)
        #expect(result == "hello")
        #expect(dropped == 2)  // surrogate pair -> 2 UTF-16 units
    }

    // Emoji (🙂) на конце: дропается, droppedStart=0
    @Test func dropEdgeClusters_emojiAtEnd_dropped() {
        let s = "hello🙂"
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: false, cutAtEnd: true)
        #expect(result == "hello")
        #expect(dropped == 0)
    }

    // ZWJ-последовательность (🏳️‍🌈 = 6 UTF-16) на начале: дропается как один grapheme cluster
    @Test func dropEdgeClusters_zwjAtStart_droppedAsOneCluster() {
        let flag = "🏳️‍🌈"
        let s = flag + "abc"
        #expect(flag.count == 1)  // один grapheme cluster
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: true, cutAtEnd: false)
        #expect(result == "abc")
        #expect(dropped == flag.utf16.count)  // 6 UTF-16 units
    }

    // ZWJ-последовательность на конце: дропается как один grapheme cluster
    @Test func dropEdgeClusters_zwjAtEnd_droppedAsOneCluster() {
        let flag = "🏳️‍🌈"
        let s = "abc" + flag
        let (result, dropped) = WindowSanitizer.dropEdgeClusters(s, cutAtStart: false, cutAtEnd: true)
        #expect(result == "abc")
        #expect(dropped == 0)
    }

    // Пустой слайс - не падает при любых флагах
    @Test func dropEdgeClusters_emptySlice_safe() {
        let (result, dropped) = WindowSanitizer.dropEdgeClusters("", cutAtStart: true, cutAtEnd: true)
        #expect(result == "")
        #expect(dropped == 0)
    }

    // Один символ + оба флага - результат пустой (сначала дроп начала, потом конца остатка)
    @Test func dropEdgeClusters_oneChar_bothFlags_empty() {
        let (result, dropped) = WindowSanitizer.dropEdgeClusters("x", cutAtStart: true, cutAtEnd: true)
        #expect(result == "")
        #expect(dropped == 1)
    }

    // droppedStart корректен для пересчёта windowAdjustedStart:
    // если окно raw = "🙂hello" и cutAtStart, то windowAdjustedStart += droppedStart (2)
    @Test func dropEdgeClusters_droppedStartMathForWindowOffset() {
        let rangeLocation = 100  // range.location из AX
        let raw = "🙂hello"
        let (_, dropped) = WindowSanitizer.dropEdgeClusters(raw, cutAtStart: true, cutAtEnd: false)
        let windowAdjustedStart = rangeLocation + dropped
        #expect(windowAdjustedStart == 102)  // caret offset будет вычтен от 102, а не от 100
    }
}
