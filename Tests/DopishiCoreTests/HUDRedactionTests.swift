import Testing
@testable import DopishiCore

@Suite struct HUDRedactionTests {
    @Test func emptyText() { #expect(HUDRedaction.summarize("") == "пусто") }
    @Test func cyrillicSummary() { #expect(HUDRedaction.summarize("привет") == "6 симв., кириллица") }
    @Test func latinSummary() { #expect(HUDRedaction.summarize("hi") == "2 симв., латиница") }
    @Test func noRealCharactersLeak() {
        #expect(!HUDRedaction.summarize("секрет").contains("секрет"))
    }
}
