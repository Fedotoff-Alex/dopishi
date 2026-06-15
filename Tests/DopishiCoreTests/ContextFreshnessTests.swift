import Testing
import CoreGraphics
@testable import DopishiCore

@Suite struct ContextFreshnessTests {
    private func ctx(_ preceding: String, typed: String) -> EditingContext {
        EditingContext(precedingText: preceding, caretScreenRect: .zero, appBundleId: "x",
                       capability: .full, isSecure: false, typedSinceFocus: typed)
    }

    @Test func emptyBufferTrustsAX() {
        #expect(ContextFreshness.isFresh(ctx("давай про", typed: "")))
    }

    @Test func prefixEndingWithTypedIsFresh() {
        // Поле было пустым, набрано "давай про", AX догнал.
        #expect(ContextFreshness.isFresh(ctx("давай про", typed: "давай про")))
    }

    @Test func staleAXMissingLatestCharsDetected() {
        // Баг из Claude: AX отдаёт "давай ", а напечатано уже "давай про" -> устарел.
        #expect(!ContextFreshness.isFresh(ctx("давай ", typed: "давай про")))
        #expect(!ContextFreshness.isFresh(ctx("давай п", typed: "давай про")))
    }

    @Test func preExistingTextWithFreshTail() {
        // В поле было "Привет, ", дописали "как дела" - AX свежий оканчивается на набранное.
        #expect(ContextFreshness.isFresh(ctx("Привет, как дела", typed: "как дела")))
        // AX отстал на хвост -> устарел.
        #expect(!ContextFreshness.isFresh(ctx("Привет, как де", typed: "как дела")))
    }

    // Регрессия (живой UAT, TextEdit): после Esc буфер оставался рассинхронным с AX, и
    // freshness-guard НАВСЕГДА отвергал подсказки (вечный staleContext до смены фокуса).
    // Фикс: Esc сбрасывает буфер, как все пути смены состояния поля. Контракт: рассинхрон
    // -> заклинило; пустой буфер (после reset) -> снова доверяем AX -> подсказки вернулись.
    @Test func resetUnwedgesDesyncedBufferAfterDismiss() {
        let desynced = "привет звонко"
        // Буфер разошёлся с тем, что показывает AX (фантомное состояние) -> заклинило.
        #expect(!ContextFreshness.isFresh(ctx("привет к", typed: desynced)))
        // Esc -> buffer.reset() -> пустой буфер -> freshness снова true (recovery).
        let recovered = KeystrokeBuffer().appending(desynced).reset()
        #expect(ContextFreshness.isFresh(ctx("привет к", typed: recovered.text)))
    }
}
