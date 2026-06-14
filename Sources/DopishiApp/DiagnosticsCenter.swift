import Foundation
import CoreGraphics
import DopishiCore
import DopishiMemory

/// Снимок «здоровья» приложения: права, модель, мастер-тумблер и фичи. Обновляется из
/// AppDelegate.refresh (каждые 2с). Equatable - чтобы не дёргать UI без изменений.
struct DiagnosticsRuntime: Equatable {
    var accessibility = false
    var inputMonitoring = false
    var screenRecording = false
    var monitorRunning = false
    var masterEnabled = false
    var modelFile = "-"
    var modelPresent = false
    // Фичи (как сейчас сконфигурированы; учитывают мастер-тумблер).
    var layout = false
    var manualLayout = false
    var autocorrect = false
    var electron = false
    var clipboard = false
    var memory = false
    var screenContext = false

    static let empty = DiagnosticsRuntime()
}

/// Снимок текущего поля ввода (из последнего EditingContext). Каналы контекста - превью
/// (nil = в контексте данных нет; вкл/выкл считает View по DiagnosticsRuntime).
struct DiagnosticsContext: Equatable {
    var app = "-"
    var tier = "-"
    var secure = false
    var profile = "-"
    var caret = "-"
    var ocrPreview: String?
    var clipboardPreview: String?
    var memoryPreview: String?

    static let empty = DiagnosticsContext()

    /// Русский ярлык категории профиля приложения.
    private static func profileLabel(_ c: AppCategory) -> String {
        switch c {
        case .terminal: return "терминал (молчит)"
        case .codeEditor: return "редактор кода (молчит)"
        case .browser: return "браузер"
        case .native: return "нативное"
        case .unknown: return "неизвестно"
        }
    }

    static func from(_ ctx: EditingContext) -> DiagnosticsContext {
        let caret = ctx.caretScreenRect.map {
            "(\(Int($0.minX)),\(Int($0.minY))) \(Int($0.width))x\(Int($0.height))"
        } ?? "-"
        let ocr = ctx.ocr.map { $0.windowText.isEmpty ? "(пусто)" : String($0.windowText.prefix(80)) }
        let clip = ctx.clipboard.map { String($0.prefix(80)) }
        let mem = ctx.memory.map { String($0.prefix(80)) }
        return DiagnosticsContext(
            app: ctx.appBundleId ?? "-",
            tier: ctx.capability.rawValue,
            secure: ctx.isSecure,
            profile: profileLabel(AppProfile.category(for: ctx.appBundleId)),
            caret: caret,
            ocrPreview: ocr,
            clipboardPreview: clip,
            memoryPreview: mem)
    }
}

/// Снимок метрик латентности подсказок (p50/p95). Обновляется при открытии панели диагностики.
struct LatencyMetrics: Equatable {
    var appBundleId: String?
    var p50FirstMs: Int = 0
    var p95FirstMs: Int = 0
    var p50TotalMs: Int = 0
    var p95TotalMs: Int = 0
    var p50AXReadMs: Int = 0
    var p95AXReadMs: Int = 0
    static let empty = LatencyMetrics()
}

/// Живой центр диагностики. Источники пишут сюда, панель читает через @ObservedObject.
/// Без побочных эффектов на пайплайн подсказок (только наблюдение).
@MainActor
final class DiagnosticsCenter: ObservableObject {
    @Published private(set) var runtime = DiagnosticsRuntime.empty
    @Published private(set) var context = DiagnosticsContext.empty
    @Published private(set) var lastOutcome = "-"
    @Published private(set) var updatedAt: Date?
    @Published private(set) var latencyMetrics: LatencyMetrics = .empty
    @Published private(set) var refusalCounts: [String: Int] = [:]

    private var eventStore: SuggestionEventStore?

    /// Последние замеры длительности read() (мс). Окно 200 - p50/p95 стабильны, память ограничена.
    /// Пишется с @MainActor (ContextProbe.buildContext @MainActor) - локов не нужно.
    private var axReadSamples: [Int] = []

    func setEventStore(_ store: SuggestionEventStore?) { eventStore = store }

    /// Записать длительность одного read() (мс) и пересчитать p50/p95 «AX read ms».
    /// Пересчёт синхронный (данные in-process), через LatencyStats.percentiles.
    func recordAXReadMs(_ ms: Int) {
        axReadSamples.append(ms)
        if axReadSamples.count > 200 { axReadSamples.removeFirst(axReadSamples.count - 200) }
        let pct = LatencyStats.percentiles(axReadSamples)
        var m = latencyMetrics
        m.p50AXReadMs = pct.p50
        m.p95AXReadMs = pct.p95
        setLatencyMetrics(m)
    }

    func setLatencyMetrics(_ m: LatencyMetrics) {
        guard m != latencyMetrics else { return }
        latencyMetrics = m
    }

    func setRefusalCounts(_ counts: [String: Int]) {
        guard counts != refusalCounts else { return }
        refusalCounts = counts
    }

    func setRuntime(_ r: DiagnosticsRuntime) {
        guard r != runtime else { return }
        runtime = r
    }

    func setContext(_ ctx: EditingContext) {
        let c = DiagnosticsContext.from(ctx)
        guard c != context else { return }
        context = c
        updatedAt = Date()
    }

    func setOutcome(_ o: SuggestionOutcome) {
        let label = o.label
        guard label != lastOutcome else { return }
        lastOutcome = label
        updatedAt = Date()
    }

    /// Подтянуть live-метрики из хранилища событий. Зовётся при открытии панели (onAppear/openDiagnostics).
    /// eventStore == nil (телеметрия выключена) -> метрики не обновляются (пустые).
    func refreshLatencyMetrics() async {
        guard let store = eventStore else { return }
        let app = context.app == "-" ? nil : context.app
        let first = await store.percentiles(appBundleId: app)
        let total = await store.percentilesTotal(appBundleId: app)
        let refusals = await store.refusalCounts()
        setLatencyMetrics(LatencyMetrics(appBundleId: context.app,
            p50FirstMs: first.p50, p95FirstMs: first.p95,
            p50TotalMs: total.p50, p95TotalMs: total.p95,
            p50AXReadMs: latencyMetrics.p50AXReadMs, p95AXReadMs: latencyMetrics.p95AXReadMs))
        setRefusalCounts(refusals)
    }
}
