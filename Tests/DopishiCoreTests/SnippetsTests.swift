import Testing
import Foundation
@testable import DopishiCore

@Suite struct ColonTriggerTests {
    @Test func extractsTokenAfterSpaceOrStart() {
        #expect(ColonTrigger.token(in: "привет :sig")?.name == "sig")
        #expect(ColonTrigger.token(in: ":sig")?.token == ":sig")
    }
    @Test func rejectsMidWordColon() {
        #expect(ColonTrigger.token(in: "http://") == nil)
        #expect(ColonTrigger.token(in: "10:30") == nil)
        #expect(ColonTrigger.token(in: "текст:") == nil)   // пустое имя
    }
}

@Suite struct SnippetCatalogTests {
    @Test func parsesLines() {
        let s = SnippetCatalog.parse("sig: С уважением, Алекс\naddr: Павловская 27с1\n\nкривая строка без двоеточия")
        #expect(s["sig"] == "С уважением, Алекс")
        #expect(s["addr"] == "Павловская 27с1")
        #expect(s.count == 2)
    }
    @Test func parseIsCaseInsensitiveByName() {
        let s = SnippetCatalog.parse("Sig: текст")
        #expect(SnippetCatalog.expansion(name: "sig", custom: s) == "текст")
        #expect(SnippetCatalog.expansion(name: "SIG", custom: s) == "текст")
    }
    @Test func builtinDateAndTime() {
        let now = Date(timeIntervalSince1970: 1781258400)   // фиксированный момент
        let d = SnippetCatalog.expansion(name: "date", custom: [:], now: now)
        let t = SnippetCatalog.expansion(name: "time", custom: [:], now: now)
        #expect(d?.count == 10)            // dd.MM.yyyy
        #expect(d?.contains(".2026") == true)
        #expect(t?.count == 5)             // HH:mm
    }
    @Test func customOverridesBuiltin() {
        #expect(SnippetCatalog.expansion(name: "date", custom: ["date": "своя дата"]) == "своя дата")
    }
    @Test func unknownIsNil() {
        #expect(SnippetCatalog.expansion(name: "nope", custom: [:]) == nil)
    }
}
