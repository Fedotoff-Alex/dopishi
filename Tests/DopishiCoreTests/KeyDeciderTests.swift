import Testing
@testable import DopishiCore

@Suite struct KeyDeciderTests {
    @Test func hotkeyAlwaysSuggestsAndSwallows() {
        let d = KeyDecider.decideKeyDown(keyCode: 38, control: true, option: true, suggestionActive: false)
        #expect(d == KeyDecision(action: .suggest, swallow: true))
    }
    @Test func tabAcceptsOnlyWhenActive() {
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false, suggestionActive: true)
                == KeyDecision(action: .accept, swallow: true))
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false, suggestionActive: false)
                == KeyDecision(action: .none, swallow: false))
    }
    @Test func shiftTabAcceptsAllOnlyWhenActive() {
        // Ровно Shift+Tab при активной подсказке = вся подсказка.
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false,
                                         command: false, shift: true, suggestionActive: true)
                == KeyDecision(action: .acceptAll, swallow: true))
        // Без подсказки Shift+Tab проходит насквозь (фокус-навигация).
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false,
                                         command: false, shift: true, suggestionActive: false)
                == KeyDecision(action: .none, swallow: false))
        // Голый Tab при активной подсказке = слово (не acceptAll).
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false,
                                         command: false, shift: false, suggestionActive: true)
                == KeyDecision(action: .accept, swallow: true))
        // Cmd+Shift+Tab НЕ acceptAll (модификатор-аккорд) - даёт accept, не ломаем спец-кейс.
        #expect(KeyDecider.decideKeyDown(keyCode: 48, control: false, option: false,
                                         command: true, shift: true, suggestionActive: true).action
                == .accept)
    }
    @Test func escDismissesOnlyWhenActive() {
        #expect(KeyDecider.decideKeyDown(keyCode: 53, control: false, option: false, suggestionActive: true)
                == KeyDecision(action: .dismiss, swallow: true))
        #expect(KeyDecider.decideKeyDown(keyCode: 53, control: false, option: false, suggestionActive: false)
                == KeyDecision(action: .none, swallow: false))
    }
    @Test func escUndoesCorrectionWhenNoSuggestion() {
        // Esc без подсказки, но после автоправки - откатывает правку.
        #expect(KeyDecider.decideKeyDown(keyCode: 53, control: false, option: false,
                                         suggestionActive: false, correctionUndoable: true)
                == KeyDecision(action: .undoCorrection, swallow: true))
        // Активная подсказка имеет приоритет - Esc её скрывает, не откатывает правку.
        #expect(KeyDecider.decideKeyDown(keyCode: 53, control: false, option: false,
                                         suggestionActive: true, correctionUndoable: true)
                == KeyDecision(action: .dismiss, swallow: true))
        // Ни того ни другого - Esc проходит насквозь.
        #expect(KeyDecider.decideKeyDown(keyCode: 53, control: false, option: false,
                                         suggestionActive: false, correctionUndoable: false)
                == KeyDecision(action: .none, swallow: false))
    }
    @Test func plainKeyPasses() {
        #expect(KeyDecider.decideKeyDown(keyCode: 2, control: false, option: false, suggestionActive: true)
                == KeyDecision(action: .none, swallow: false))
    }
    @Test func hotkeyNeedsBothModifiers() {
        #expect(KeyDecider.decideKeyDown(keyCode: 38, control: true, option: false, suggestionActive: false)
                == KeyDecision(action: .none, swallow: false))
    }
    @Test func ctrlOptZ_isUndo() {
        let d = KeyDecider.decideKeyDown(keyCode: 6, control: true, option: true, suggestionActive: false)
        #expect(d.action == .undo)
        #expect(d.swallow == true)
    }
}
