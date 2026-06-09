import Testing
import Foundation
@testable import DopishiCore

// Поведенческая спецификация ClipboardRelevanceFilter (swift-testing).
private final class Clock { var now: Date; init(_ d: Date) { now = d } }

@Suite struct ClipboardRelevanceFilterTests {
    @Test func nilClipboardReturnsNil() {
        let f = ClipboardRelevanceFilter()
        #expect(f.filter(clipboard: nil, pasteboardChangeCount: 1, precedingText: "hello world") == nil)
    }

    @Test func firstObservationReturnsNilEvenWithOverlap() {
        let f = ClipboardRelevanceFilter()
        // Первое наблюдение фиксирует baseline и отказывает даже при совпадении токенов.
        #expect(f.filter(clipboard: "meeting agenda", pasteboardChangeCount: 42,
                         precedingText: "the meeting starts soon") == nil)
    }

    @Test func firstChangeAfterBaselineReturnsContentWhenOverlapMatches() {
        let f = ClipboardRelevanceFilter()
        _ = f.filter(clipboard: "x", pasteboardChangeCount: 42, precedingText: "")   // baseline
        #expect(f.filter(clipboard: "meeting agenda for Thursday", pasteboardChangeCount: 43,
                         precedingText: "Let's discuss the meeting") == "meeting agenda for Thursday")
    }

    @Test func freshNoOverlapReturnsNil() {
        let f = ClipboardRelevanceFilter()
        _ = f.filter(clipboard: "x", pasteboardChangeCount: 1, precedingText: "")
        #expect(f.filter(clipboard: "SELECT * FROM users", pasteboardChangeCount: 2,
                         precedingText: "Dear hiring manager") == nil)
    }

    @Test func shortTokensIgnoredInOverlap() {
        let f = ClipboardRelevanceFilter()
        _ = f.filter(clipboard: "x", pasteboardChangeCount: 1, precedingText: "")
        // Общие токены только <3 символов -> токенайзер их игнорит -> нет пересечения.
        #expect(f.filter(clipboard: "a b c", pasteboardChangeCount: 2, precedingText: "a b c d e") == nil)
    }

    @Test func tokenOverlapCaseInsensitive() {
        let f = ClipboardRelevanceFilter()
        _ = f.filter(clipboard: "x", pasteboardChangeCount: 1, precedingText: "")
        #expect(f.filter(clipboard: "Deployment Pipeline", pasteboardChangeCount: 2,
                         precedingText: "the deployment is running") == "Deployment Pipeline")
    }

    @Test func staleClipboardReturnsNil() {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let f = ClipboardRelevanceFilter(dateProvider: { clock.now })
        _ = f.filter(clipboard: "c", pasteboardChangeCount: 1, precedingText: "")   // baseline
        // свежая копия (count 2) в t=1000 - засекает часы
        _ = f.filter(clipboard: "second content matching", pasteboardChangeCount: 2,
                     precedingText: "second content")
        clock.now = clock.now.addingTimeInterval(301)   // прошло > 300с
        #expect(f.filter(clipboard: "second content matching", pasteboardChangeCount: 2,
                         precedingText: "second content") == nil)
    }

    @Test func newCopyResetsStalenessClock() {
        let clock = Clock(Date(timeIntervalSince1970: 1000))
        let f = ClipboardRelevanceFilter(dateProvider: { clock.now })
        _ = f.filter(clipboard: "a", pasteboardChangeCount: 1, precedingText: "")   // baseline
        _ = f.filter(clipboard: "first matching content", pasteboardChangeCount: 2,
                     precedingText: "first content")   // копия в t=1000
        clock.now = clock.now.addingTimeInterval(301)   // count 2 устарел
        // НОВАЯ копия (count 3) сбрасывает часы -> снова свежо
        #expect(f.filter(clipboard: "second content matching prefix", pasteboardChangeCount: 3,
                         precedingText: "second content") == "second content matching prefix")
    }
}
