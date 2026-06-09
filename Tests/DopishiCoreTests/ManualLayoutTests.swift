import Testing
@testable import DopishiCore

@Suite struct ManualLayoutTests {
    @Test func latinToRussian() {
        let r = ManualLayout.convert("ghbdtn")
        #expect(r?.replacement == "привет")
        #expect(r?.language == "ru")
    }
    @Test func cyrillicToEnglish() {
        let r = ManualLayout.convert("руддщ")
        #expect(r?.replacement == "hello")
        #expect(r?.language == "en")
    }
    @Test func forcedEvenIfValidWord() {
        let r = ManualLayout.convert("привет")
        #expect(r?.replacement == "ghbdtn")
        #expect(r?.language == "en")
    }
    @Test func neutralReturnsNil() {
        #expect(ManualLayout.convert("123") == nil)
        #expect(ManualLayout.convert("") == nil)
    }
    @Test func singleCharNotConverted() {
        // Одиночный символ не конвертируем - источник бага "добрался"->"до,рался" ("б"->",").
        #expect(ManualLayout.convert("б") == nil)
        #expect(ManualLayout.convert("z") == nil)
        // Слово из 2+ символов конвертируется как раньше.
        #expect(ManualLayout.convert("да")?.replacement == "lf")
    }
}
