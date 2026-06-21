import Testing
@testable import DopishiApp

// Счётчик secret-dropped в DiagnosticsCenter (D-06, MEM-06).
// КРИТИЧНО: в метрику попадает ТОЛЬКО число. Сырой текст секрета НИКОГДА не передаётся
// в DiagnosticsCenter - noteSecretDropped() не принимает текст ни в каком виде.
// DiagnosticsCenter - @MainActor, поэтому сьют @MainActor.
@Suite @MainActor struct DiagnosticsSecretTests {
    @Test func counterStartsAtZero() {
        let center = DiagnosticsCenter()
        #expect(center.secretDropped == 0)
    }

    @Test func noteIncrements() {
        let center = DiagnosticsCenter()
        center.noteSecretDropped()
        center.noteSecretDropped()
        center.noteSecretDropped()
        #expect(center.secretDropped == 3)
    }

    // D-06: noteSecretDropped не принимает String-аргумент - вызов без текста компилируется
    // (сигнатура без текста проверяется компиляцией этого вызова + grep в acceptance).
    @Test func apiHasNoTextParameter() {
        let center = DiagnosticsCenter()
        center.noteSecretDropped()
        #expect(center.secretDropped == 1)
    }
}
