import Testing
import Foundation
@testable import DopishiCore

/// MEM-02 (Phase 6): adaptive policy per-app - floor/explore/cold-start/decay.
@Suite struct AdaptivePolicyTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let global = AdaptiveParams(minConfidence: -3.0, maxWords: 6, showRate: 1.0)

    private func stats(total: Int, shown: Int, accepted: Int,
                       lastDaysAgo: Double = 0.1) -> AppSuggestStats {
        AppSuggestStats(total: total, shown: shown, accepted: accepted,
                        lastEventAt: now.addingTimeInterval(-lastDaysAgo * 86400))
    }

    // SC: cold-start - global defaults первые 30 событий.
    @Test func coldStartUsesGlobalDefaults() {
        let p = AdaptivePolicy.params(global: global, stats: stats(total: 29, shown: 20, accepted: 0), now: now)
        #expect(p == global)
        let none = AdaptivePolicy.params(global: global, stats: nil, now: now)
        #expect(none == global)
    }

    // SC: при полном отсутствии истории подсказки идут с разумной частотой (showRate 1.0).
    @Test func coldStartNeverSuppresses() {
        let p = AdaptivePolicy.params(global: global, stats: nil, now: now)
        #expect(p.showRate == 1.0)
        for i in 0..<50 {
            #expect(AdaptivePolicy.admits(requestIndex: i, showRate: p.showRate))
        }
    }

    // SC: decay - сброс к global после 7 дней простоя.
    @Test func decayResetsToGlobalAfterSevenIdleDays() {
        let idle = stats(total: 100, shown: 80, accepted: 40, lastDaysAgo: 8)
        #expect(AdaptivePolicy.params(global: global, stats: idle, now: now) == global)
        let active = stats(total: 100, shown: 80, accepted: 40, lastDaysAgo: 6)
        #expect(AdaptivePolicy.params(global: global, stats: active, now: now) != global)
    }

    // SC-3: после N>30 событий с принятиями порог/длина отличаются от global.
    @Test func matureStatsDivergeFromGlobal() {
        let good = stats(total: 50, shown: 40, accepted: 20)   // acceptance 0.5
        let p = AdaptivePolicy.params(global: global, stats: good, now: now)
        #expect(p.minConfidence < global.minConfidence)   // смелее: мягче порог
        #expect(p.maxWords > global.maxWords)             // длиннее дополнение
        #expect(p.showRate == 1.0)
    }

    // SC: floor >= 0.3 - policy не молчит бесконечно даже при нулевом принятии.
    @Test func zeroAcceptanceHitsFloorNotSilence() {
        let bad = stats(total: 100, shown: 90, accepted: 0)
        let p = AdaptivePolicy.params(global: global, stats: bad, now: now)
        #expect(p.showRate >= AdaptivePolicy.showRateFloor)
        #expect(p.showRate == AdaptivePolicy.showRateFloor)
        #expect(p.minConfidence > global.minConfidence)   // строже порог
        #expect(p.maxWords < global.maxWords)             // короче
        // Прореживание admits: на 70 тактах прошло >= floor-доли (с учётом explore).
        let admitted = (0..<70).filter { AdaptivePolicy.admits(requestIndex: $0, showRate: p.showRate) }.count
        #expect(admitted >= 21)
        #expect(admitted < 50)   // но и не все - прореживание реально работает
    }

    // SC: explore - каждый exploreEvery-й запрос идёт с global-параметрами (разведка),
    // данные продолжают собираться и policy может выйти из строгого режима.
    @Test func exploreTickUsesGlobalParams() {
        let strict = AdaptiveParams(minConfidence: -2.5, maxWords: 4, showRate: 0.3)
        let onExplore = AdaptivePolicy.paramsForRequest(index: AdaptivePolicy.exploreEvery * 2,
                                                        adaptive: strict, global: global)
        #expect(onExplore == global)
        let regular = AdaptivePolicy.paramsForRequest(index: AdaptivePolicy.exploreEvery * 2 + 1,
                                                      adaptive: strict, global: global)
        #expect(regular == strict)
    }

    // Explore-такт всегда пропускается в генерацию, даже при floor-прореживании.
    @Test func exploreTickAlwaysAdmitted() {
        for k in 0..<10 {
            #expect(AdaptivePolicy.admits(requestIndex: k * AdaptivePolicy.exploreEvery, showRate: 0.3))
        }
    }

    // Средняя зона принятия - global (не дёргаем параметры без сигнала).
    @Test func midAcceptanceKeepsGlobal() {
        let mid = stats(total: 60, shown: 50, accepted: 9)   // acceptance 0.18
        #expect(AdaptivePolicy.params(global: global, stats: mid, now: now) == global)
    }

    // maxWords не выходит за пределы [2, 12] при экстремальных global.
    @Test func wordBoundsClamped() {
        let good = stats(total: 50, shown: 40, accepted: 30)
        let wide = AdaptivePolicy.params(global: AdaptiveParams(minConfidence: -3, maxWords: 11, showRate: 1),
                                         stats: good, now: now)
        #expect(wide.maxWords <= 12)
        let bad = stats(total: 100, shown: 90, accepted: 0)
        let narrow = AdaptivePolicy.params(global: AdaptiveParams(minConfidence: -3, maxWords: 3, showRate: 1),
                                           stats: bad, now: now)
        #expect(narrow.maxWords >= 2)
    }
}
