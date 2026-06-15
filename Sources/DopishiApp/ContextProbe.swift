import AppKit
import DopishiCore

/// Связывает ввод (InputMonitor) с чтением AX (AccessibilityReader)
/// и собирает EditingContext, отдавая его наблюдателю (HUD).
@MainActor
final class ContextProbe {
    var onContext: ((EditingContext) -> Void)?
    var onSuggest: (() -> Void)?
    var onAccept: (() -> Void)?
    var onAcceptAll: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onUndo: (() -> Void)?
    var onWordCompleted: ((String) -> Bool)?
    var onLayoutSwitch: ((String, String?) -> Void)?
    /// После Tab/grave-вставки probe сам перечитывает новую каретку/текст и просит контроллер
    /// продолжить фразу (остаток из памяти или генерация). AX-события на синтетику нет.
    var onContinueAfterAccept: ((EditingContext) -> Void)?
    /// Длительность последнего AccessibilityReader.read() в мс (для DiagnosticsCenter, D-07/D-08).
    var onAXReadMs: ((Int) -> Void)?

    /// bundleId приложений, где Dopishi не активничает.
    var excludedBundleIds: Set<String> = []

    /// Включать AXEnhancedUserInterface для Electron-приложений (тумблер настроек).
    var enhancedUIEnabled = false

    /// Контекст буфера обмена (opt-in). AppDelegate включает по настройке.
    var clipboardEnabled = false
    private let clipboardFilter = ClipboardRelevanceFilter()
    private var lastClipChangeCount = -1
    private var lastClipText: String?
    private var lastClipSanitized: String?

    private let monitor = InputMonitor()
    private var buffer = KeystrokeBuffer()
    private var lastAppBundleId: String?
    private var lastWindowId: CGWindowID?
    private var lastOcrPokeAt = Date.distantPast
    private var pollTask: Task<Void, Never>?
    /// Debounce-задача OCR: запуск распознавания экрана только ПОСЛЕ паузы набора (не каждый тик).
    private var ocrRefreshTask: Task<Void, Never>?

    /// OCR-контекст экрана (opt-in). AppDelegate включает provider.enabled по настройке.
    let ocrProvider = WindowOCRProvider()

    /// Локальная память контекста (opt-in). AppDelegate включает по настройке.
    let memoryProvider = MemoryProvider()
    private(set) var lastMemThreadKey: String?
    private var lastMemFieldText: String?

    /// Хелпер расчёта миллисекунд из Duration (ContinuousClock). Дубль из SuggestionController.
    private static func ms(_ d: Duration) -> Int {
        let (sec, atto) = d.components
        return Int(sec) * 1000 + Int(atto / 1_000_000_000_000_000)
    }

    @discardableResult
    func start() -> Bool {
        monitor.onEvent = { [weak self] event in
            // onEvent is a non-isolated closure type; hop to main actor
            // before touching @MainActor state on self.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch event {
                case .didType(let s):
                    self.monitor.correctionUndoable = false   // новое нажатие закрывает окно отката Esc
                    self.buffer = self.buffer.appending(s)
                    let ctx = self.recompute()
                    if let ch = s.last, WordBoundary.isBoundary(ch), !ctx.isSecure, ctx.capability != .none,
                       AppPolicy.isAllowed(bundleId: ctx.appBundleId, excluded: self.excludedBundleIds) {
                        // Автокоррекция/раскладка срабатывают на ГРАНИЦЕ слова - их guard требует,
                        // чтобы текст оканчивался границей. В Electron AX отстаёт и только что
                        // набранную границу ещё не показывает -> берём текст из буфера (немедленная
                        // правда о наборе, с границей). В нативных полях AX уже свежий - берём его.
                        let endsWithBoundary = ctx.precedingText.last.map(WordBoundary.isBoundary) ?? false
                        let completionText = endsWithBoundary ? ctx.precedingText : self.buffer.text
                        // Если коррекция/раскладка ВСТАВИЛА исправление - буфер рассинхронился с
                        // AX (синтетика не буферится), сбрасываем, иначе freshness-guard
                        // заблокирует все следующие подсказки.
                        if self.onWordCompleted?(completionText) == true {
                            self.buffer = self.buffer.reset()
                            self.monitor.correctionUndoable = true   // была автоправка -> Esc откатит
                        }
                    }
                    // Поллинг-перечитка нужна ТОЛЬКО когда AX отстаёт от набора (Electron-лаг).
                    // В нативных полях синхронный recompute уже свежий -> isFresh -> поллинг бы
                    // крутил все 5 итераций впустую (текст не меняется, ранний выход не срабатывает,
                    // каждая итерация = полный buildContext + пайплайн + OCR). Гейтим по свежести
                    // (контентно, без детекта bundle-id): нет лага - нет поллинга.
                    if !ContextFreshness.isFresh(ctx) {
                        self.scheduleElectronRecompute(previousText: ctx.precedingText)
                    }
                case .backspace:
                    self.pollTask?.cancel()
                    self.buffer = self.buffer.backspacing()
                    self.recompute()
                case .caretMayHaveMoved:
                    self.pollTask?.cancel()
                    // каретка сдвинулась (клик/стрелки/Enter) - фолбэк-буфер больше не непрерывен
                    self.buffer = self.buffer.reset()
                    let moved = self.recompute()
                    // Enter в чате чистит поле ПОСЛЕ того, как приложение обработает клавишу -
                    // мгновенная перечитка видит ещё СТАРЫЙ текст, и ghost висел бы над пустым
                    // полем до следующего ввода. Короткий поллинг (force: и для нативных
                    // приложений, не только Electron) дочитывает новое состояние поля.
                    self.scheduleElectronRecompute(previousText: moved.precedingText, force: true)
                case .suggestRequested:
                    self.onSuggest?()
                case .acceptRequested:
                    self.onAccept?()
                    // Инъекция (вставка слова) обходит буфер (синтетика помечена и игнорится),
                    // поэтому буфер рассинхронится с AX. Сбрасываем - иначе freshness-guard
                    // отвергнет все следующие подсказки (буфер перестанет быть суффиксом AX).
                    self.buffer = self.buffer.reset()
                    self.scheduleAcceptContinue()
                case .acceptAllRequested:
                    self.onAcceptAll?()
                    self.buffer = self.buffer.reset()
                    self.scheduleAcceptContinue()
                case .undoCorrectionRequested:
                    // Esc после автоправки - откат той же правки (как ⌃⌥Z), затем закрываем окно.
                    self.onUndo?()
                    self.monitor.correctionUndoable = false
                    self.buffer = self.buffer.reset()
                case .dismissRequested:
                    self.onDismiss?()
                    // Esc = "перестать предлагать здесь". Сбрасываем буфер, как и все пути,
                    // меняющие состояние поля (accept/undo/correction/layout): иначе при любом
                    // рассинхроне буфера с AX freshness-guard НАВСЕГДА блокирует подсказки в
                    // этом поле (вечный staleContext до смены фокуса - баг из живого UAT в
                    // TextEdit). Бонус: Esc становится recovery-жестом, если что-то заклинило.
                    self.buffer = self.buffer.reset()
                case .undoRequested:
                    self.onUndo?()
                    self.buffer = self.buffer.reset()   // откат тоже инъекция - буфер невалиден
                case .layoutSwitchRequested:
                    let ctx = self.recompute()
                    // Ручной тап работает и в textOnly (напр. Electron/Claude): конверсия
                    // последнего слова не требует позиции каретки - только текст (из AX или
                    // фолбэк-буфера), замена идёт backspace+вставкой. Явный жест пользователя
                    // плюс откат ⌃⌥Z страхуют от неточности буфера. Отсекаем secure.
                    // Выделение (selectedText) - отдельный путь: его конвертируем даже при
                    // capability == .none (текста до каретки нет, но выделенное AX отдал).
                    let hasSelection = !(ctx.selectedText?.isEmpty ?? true)
                    if (ctx.capability != .none || hasSelection), !ctx.isSecure,
                       AppPolicy.isAllowed(bundleId: ctx.appBundleId, excluded: self.excludedBundleIds) {
                        self.onLayoutSwitch?(ctx.precedingText, ctx.selectedText)
                        self.buffer = self.buffer.reset()   // замена слова - инъекция, буфер невалиден
                    }
                }
            }
        }
        return monitor.start()
    }

    func stop() {
        pollTask?.cancel()
        ocrRefreshTask?.cancel()
        monitor.stop()
    }

    func setSuggestionActive(_ active: Bool) { monitor.suggestionActive = active }

    /// В Chromium/Electron AX-дерево обновляется ПОСЛЕ обработки нажатия приложением,
    /// поэтому синхронный recompute даёт текст без последнего символа. Перечитываем
    /// несколько раз с нарастающей задержкой, пока текст не изменится (или не выйдет таймаут).
    /// recompute() сам вызовет onContext со свежим контекстом - подсказка перестроится.
    /// force: поллить независимо от тумблера Electron - для caret-move/Enter, где отложенное
    /// обновление поля (очистка после отправки) случается и в нативных приложениях.
    private func scheduleElectronRecompute(previousText: String, force: Bool = false) {
        guard enhancedUIEnabled || force else { return }   // только когда включена поддержка Electron (или force)
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            for delayMs in [25, 40, 70, 120, 150] {   // суммарно ~400 мс максимум
                try? await Task.sleep(for: .milliseconds(delayMs))
                if Task.isCancelled { return }
                guard let self else { return }
                let fresh = self.recompute()
                if fresh.precedingText != previousText { return }   // AX обновился - стоп
            }
        }
    }

    /// OCR после ПАУЗЫ набора (debounce ~700мс). Пересоздаётся на каждом тике набора, поэтому
    /// захват экрана + Vision запускаются лишь когда пользователь остановился, а не каждую
    /// секунду в процессе печати (главный источник нагрузки CPU/нейродвижка при включённом
    /// контексте экрана). Смену окна обрабатываем отдельно и немедленно (см. buildContext).
    private func scheduleOcrRefresh() {
        ocrRefreshTask?.cancel()
        ocrRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            guard let self, self.ocrProvider.enabled else { return }
            let ax = AccessibilityReader.read(enableEnhancedUI: self.enhancedUIEnabled)
            self.lastOcrPokeAt = Date()
            self.ocrProvider.onFocusedWindowChanged(
                windowId: ax.focusedWindowId,
                windowFrame: ax.focusedWindowFrame,
                caretScreenRect: ax.caretRect,
                isSecure: ax.isSecure,
                allowedApp: AppPolicy.isAllowed(bundleId: ax.appBundleId, excluded: self.excludedBundleIds),
                fieldText: ax.text ?? "")
        }
    }

    /// После Tab/grave нет AX-события (вставка синтетическая) - сами перечитываем новую каретку
    /// и текст, затем просим контроллер продолжить (остаток фразы из памяти или генерация).
    /// Лёгкая задержка даёт приложению обработать вставку (страхует Chromium/Electron-лаг AX).
    /// Идём в обход onContext/contextUpdated (через onContinueAfterAccept), иначе обычный
    /// contextUpdated сбросил бы остаток фразы до показа. Если юзер начал печатать - .didType
    /// отменит этот pollTask и продолжит обычным путём (type-through).
    private func scheduleAcceptContinue() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            guard let self else { return }
            let ctx = self.buildContext()
            self.onContinueAfterAccept?(ctx)
        }
    }

    @discardableResult
    private func recompute() -> EditingContext {
        let ctx = buildContext()
        onContext?(ctx)
        return ctx
    }

    /// Читает AX + OCR + фолбэк-буфер и собирает EditingContext, но НЕ рассылает наблюдателям.
    /// Рассылку делает вызывающий: recompute() -> onContext (обычный путь набора), accept-поллинг
    /// -> onContinueAfterAccept. Разделение нужно, чтобы после Tab не стереть остаток фразы.
    private func buildContext() -> EditingContext {
        let readStart = ContinuousClock.now
        let ax = AccessibilityReader.read(enableEnhancedUI: enhancedUIEnabled)
        onAXReadMs?(Self.ms(ContinuousClock.now - readStart))
        if ax.isSecure { buffer = buffer.reset() }   // не копим секреты
        if ax.appBundleId != lastAppBundleId {        // сменилось приложение/фокус - не тащим чужой текст
            buffer = buffer.reset()
            lastAppBundleId = ax.appBundleId
        }
        // OCR: invalidate готовый снимок на смену окна (не подмешать чужое). А захват запускаем
        // на смену окна ИЛИ периодически (>=1с), не только на смену - иначе в Electron, где
        // windowId стабильно один (или nil->fallback), захват вообще не стартовал бы. Сам захват
        // дополнительно троттлится в провайдере (4с). Генерация подсказки этого никогда не ждёт.
        let windowChanged = ax.focusedWindowId != lastWindowId
        if windowChanged {
            lastWindowId = ax.focusedWindowId
            ocrProvider.invalidate()
        }
        if ocrProvider.enabled {
            if windowChanged {
                // Смена окна - читаем сразу (свежий контекст нового поля).
                lastOcrPokeAt = Date()
                ocrRefreshTask?.cancel()
                ocrProvider.onFocusedWindowChanged(
                    windowId: ax.focusedWindowId,
                    windowFrame: ax.focusedWindowFrame,
                    caretScreenRect: ax.caretRect,
                    isSecure: ax.isSecure,
                    allowedApp: AppPolicy.isAllowed(bundleId: ax.appBundleId, excluded: excludedBundleIds),
                    fieldText: ax.text ?? "")
            } else {
                // В ПРОЦЕССЕ набора OCR не гоняем: ScreenCaptureKit + Vision (нейродвижок) дорого
                // на каждый тик. Перечитываем после ПАУЗЫ набора (debounce) - контекст нужен к
                // моменту генерации подсказки, а не на каждую клавишу. Раньше пинали раз в 1с.
                scheduleOcrRefresh()
            }
        }
        // Префикс для буфера = тот же хвост, что увидит модель (ContextBuilder режет fieldTail до 600),
        // и тот же fallback на буфер клавиш, что и precedingText (иначе в Electron AX=nil -> буфер
        // молча не срабатывал бы, хотя текст есть).
        let clipPrefix = String((ax.text ?? buffer.text).suffix(600))
        let clip = readClipboard(isSecure: ax.isSecure, appBundleId: ax.appBundleId, prefix: clipPrefix)
        // Память потока. Без СТАБИЛЬНОГО windowId память не ведём: иначе все окна без id схлопнулись
        // бы в "app:0" и приватный текст потёк бы между диалогами на ДИСКЕ (persist, 14 дней). Смену
        // потока определяем по memKey (не по OCR-флагу windowChanged - он завязан на тот же id).
        var mem: String? = nil
        if memoryProvider.enabled, let wid = ax.focusedWindowId {
            let memKey = "\(ax.appBundleId ?? "?"):\(wid)"
            if memKey != lastMemThreadKey {   // ушли из потока - пишем его последний текст
                if let prevKey = lastMemThreadKey, let prevText = lastMemFieldText, !prevText.isEmpty {
                    memoryProvider.record(threadKey: prevKey, text: prevText)
                }
                lastMemThreadKey = memKey
                lastMemFieldText = nil
                memoryProvider.setCurrentThread(memKey)
            }
            if !ax.isSecure, AppPolicy.isAllowed(bundleId: ax.appBundleId, excluded: excludedBundleIds) {
                // MEM-01: снимок «Память:» подтягивает релевантное старое (FTS5) под
                // набираемый текст. Внутри secure/excluded-гейта: запрос не строится из
                // содержимого secure-полей. Фоном + дебаунс - hot-path не ждёт БД.
                memoryProvider.noteTypingPrefix(clipPrefix)
                let newText = ax.text ?? ""
                // ax.text теперь оконный слайс (range-read, max ~1000 символов), не полный текст поля (Phase 2).
                // Shrink-эвристика работает на capped-тексте: основной кейс (Enter в чате: prev=окно, new="")
                // ловится. Частичный shrink огромного поля (>1000 реальных символов) может не сработать -
                // принятый компромисс (D-03, RESEARCH Pitfall 4): TTL памяти 7 дней, потеря несущественна.
                // Резкое сокращение поля (>50%, было существенным) = отправка/очистка/замена ->
                // пишем ПРЕ-очистный текст (главный кейс чатов: поле чистится на Enter).
                if let prev = lastMemFieldText, prev.count >= 8, newText.count * 2 < prev.count {
                    memoryProvider.record(threadKey: memKey, text: prev)
                }
                lastMemFieldText = newText.isEmpty ? nil : newText
            } else {
                lastMemFieldText = nil   // secure/excluded поле - текст не держим
            }
            mem = memoryProvider.latest
        } else if lastMemThreadKey != nil {
            // нет стабильного окна - память неактивна для этого фокуса, гасим снимок/состояние.
            lastMemThreadKey = nil
            lastMemFieldText = nil
            memoryProvider.setCurrentThread(nil)
        }
        let ctx = EditingContextBuilder.build(
            axText: ax.text,
            fallbackText: buffer.text,
            caretRect: ax.caretRect,
            appBundleId: ax.appBundleId,
            isSecure: ax.isSecure,
            axFontName: ax.caretFontName,
            axFontSize: ax.caretFontSize,
            selectedText: ax.selectedText,
            keystrokeText: buffer.text,
            ocr: ocrProvider.enabled ? ocrProvider.latest : nil,
            clipboard: clip,
            memory: mem,
            axFollowingText: ax.followingText
        )
        return ctx
    }

    /// Вкл/выкл памяти с очисткой pending-состояния. При выключении сбрасываем lastMem*, иначе
    /// после повторного включения stale-текст уходящего потока записался бы на следующей смене окна.
    func setMemoryEnabled(_ enabled: Bool) {
        memoryProvider.enabled = enabled
        if !enabled {
            lastMemThreadKey = nil
            lastMemFieldText = nil
            memoryProvider.invalidate()
        }
    }

    /// Релевантный буфер обмена для подмешивания (opt-in). Гейты как у OCR: enabled + !secure +
    /// allowedApp. changeCount - чтобы не перечитывать тот же буфер. Фильтр+дистилляция в Core.
    private func readClipboard(isSecure: Bool, appBundleId: String?, prefix: String) -> String? {
        guard clipboardEnabled, !isSecure,
              AppPolicy.isAllowed(bundleId: appBundleId, excluded: excludedBundleIds) else { return nil }
        let pb = NSPasteboard.general
        if pb.changeCount != lastClipChangeCount {
            lastClipChangeCount = pb.changeCount
            let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Секрет (ключ/пароль) дропаем на чтении; иначе кэшируем sanitize по changeCount,
            // чтобы не гонять его на каждый keystroke (distill зависит от префикса - считаем заново).
            if let s, !s.isEmpty, !ClipboardContentDistiller.looksSecret(s) {
                lastClipText = s
                lastClipSanitized = PromptContextSanitizer.sanitize(s)
            } else {
                lastClipText = nil
                lastClipSanitized = nil
            }
        }
        // Фильтр зовём всегда (он держит состояние changeCount/свежести); результат - только флаг.
        guard clipboardFilter.filter(clipboard: lastClipText, pasteboardChangeCount: pb.changeCount,
                                     precedingText: prefix) != nil,
              let sanitized = lastClipSanitized else { return nil }
        return ClipboardContentDistiller.prepared(sanitized: sanitized, prefix: prefix)
    }
}
