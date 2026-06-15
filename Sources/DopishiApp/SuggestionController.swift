import AppKit
import DopishiCore
import DopishiLLM
import DopishiMemory

/// По хоткею генерирует LLM-подсказку и стримит её в ghost-оверлей у каретки.
/// Набор/смена контекста/Esc отменяют генерацию и прячут оверлей.
@MainActor
final class SuggestionController {
    private let overlay = GhostOverlay()
    private var engine = SuggestionEngine()

    private var latest: EditingContext?
    private var task: Task<Void, Never>?
    private var currentSuggestion: String?
    private var debounceTask: Task<Void, Never>?
    /// Поколение генерации (no-flicker, PERF-02): растёт при каждом новом запросе и каждой
    /// инвалидации. Стрим показывает токены только пока его поколение текущее - закрывает
    /// гонку «отменённый task успел overlay.show() после стартa нового» (Task.cancel асинхронный).
    private var generation = 0
    /// Буфер набора на момент staleContext-отказа. Если следующий контекст пришёл с ТЕМ ЖЕ
    /// буфером (юзер не печатал - это AX догнал клавиатуру), запрашиваем подсказку сразу,
    /// без второго debounce: иначе каждый показ платил отказ + поллинг + повторный debounce
    /// (телеметрия: 3 staleContext-отказа на 1 показ - «не всегда предлагает»).
    private var staleRetryTyped: String?
    private var enabled = true
    private var debounceMs = 350
    private var minChars = 3
    private var excludedApps: Set<String> = []
    /// «Не учиться в этом приложении» (Privacy Center): запись accepted в память блокируется.
    private var memoryExcludedApps: Set<String> = []
    /// Предлагать ли исправление опечатки (вместо старой авто-замены). Тумблер autocorrect.
    private var correctionEnabled = true
    /// Личный словарь (нормализованный): слова отсюда НЕ предлагаем исправлять.
    private var customWords: Set<String> = []
    /// Пользовательские сниппеты (распарсенные из настроек): имя -> текст (UX-05).
    private var snippets: [String: String] = [:]
    /// Мгновенный предиктор (PERF-03): кандидат из принятых/памяти до ответа LLM.
    /// Гейт - memoryEnabled (SC-5: функция opt-in пользователей памяти).
    private var predictor = CachePredictor()
    private var predictorEnabled = false
    /// Текущее предложенное исправление: план замены (что показать / сколько удалить / что
    /// вставить). Показывается зелёным; Tab применяет. Держим ОТДЕЛЬНО от currentSuggestion,
    /// чтобы type-through (продолжение фразы) не путал коррекцию с дописыванием.
    private var pendingCorrection: CorrectionPlan.Fix?

    private var currentModelFile = ModelCatalog.defaultFileName

    // --- Adaptive policy (MEM-02) ---
    /// Провайдер adaptive-параметров per-app (AppDelegate -> AdaptivePolicyCenter).
    /// nil или телеметрия выключена -> global, политика молча деградирует.
    var adaptiveParamsProvider: ((_ appId: String?, _ global: AdaptiveParams) -> AdaptiveParams)?
    /// Global длина дополнения из настроек (для global-базы adaptive policy).
    private var maxWordsGlobal = 6
    /// Счётчик LLM-запросов per-app: explore-такты и Bresenham-прореживание admits.
    private var adaptiveRequestIndex: [String: Int] = [:]

    /// Минимум высоты каретки за сессию фокуса (по bundleId) - чтобы кегль не прыгал,
    /// когда AX иногда отдаёт высоту всего поля вместо строки.
    private var caretHeightFloor: [String: CGFloat] = [:]

    /// Применить настройки (из окна настроек / при старте).
    /// Смена модели пересоздаёт движок (новый лениво загрузит выбранную модель).
    func applySettings(_ s: Settings) {
        enabled = s.enabled
        debounceMs = s.debounceMs
        minChars = s.minChars
        excludedApps = Set(s.excludedBundleIds)
        memoryExcludedApps = Set(s.memoryExcludedBundleIds)
        maxWordsGlobal = s.maxCompletionWords
        correctionEnabled = s.autocorrectEnabled   // тумблер теперь = «предлагать исправление»
        customWords = CustomDictionary.normalizedSet(s.customDictionary)
        snippets = SnippetCatalog.parse(s.snippetsRaw)
        predictorEnabled = s.enabled && s.memoryEnabled
        if s.selectedModelFile != currentModelFile {
            currentModelFile = s.selectedModelFile
            engine = SuggestionEngine(fileName: s.selectedModelFile)
            if enabled { warmUp() }   // прогрев новой модели в фоне
        }
        // Длина дополнения + пользовательские указания - на лету, без перезагрузки модели.
        let e = engine
        let mw = s.maxCompletionWords
        let instr = s.writingInstructions
        Task { await e.applyRuntime(maxWords: mw, instructions: instr) }
        if !enabled { cancelAndHide() }
    }

    /// Предиктор: выучить один текст (live, на принятии подсказки).
    func predictorLearn(_ text: String) {
        predictor.learn(text)
    }

    /// Предиктор: начальная загрузка из памяти (на старте/включении памяти).
    func predictorBulkLearn(_ texts: [String]) {
        for t in texts { predictor.learn(t) }
    }

    /// Прогрев движка в фоне (первая подсказка не платит загрузку модели).
    func warmUp() {
        let e = engine
        Task { await e.warmUp() }
    }

    private func font(for ctx: EditingContext) -> NSFont {
        // Точный шрифт из AX (нативные поля) - используем напрямую, верное совпадение по размеру.
        if let name = ctx.caretFontName, let size = ctx.caretFontSize, let f = NSFont(name: name, size: size) {
            return f
        }
        if let size = ctx.caretFontSize { return .systemFont(ofSize: size) }
        // Шрифта нет (часто Electron) - оцениваем кегль по высоте каретки (стабилизированной минимумом).
        if let h = ctx.caretScreenRect?.height, h > 0 {
            let key = ctx.appBundleId ?? "-"
            let floor = min(caretHeightFloor[key] ?? h, h)
            caretHeightFloor[key] = floor
            // Ratio 0.85: без метрик шрифта (Electron, где AX-шрифт не отдаётся) оцениваем кегль
            // по высоте каретки. Замер нативного поля: caretHeight 14 -> font 12 = ratio 0.857,
            // поэтому 0.85 (раньше 0.80 давало заниженный, текст-подсказка выглядела мельче).
            return .systemFont(ofSize: GhostFontMetrics.pointSize(caretHeight: floor, fallbackRatio: 0.85))
        }
        return .systemFont(ofSize: 13)
    }

    /// Незаконченное ли слово в конце префикса. Эвристика: префикс кончается буквой И последний
    /// фрагмент НЕ словарный (misspelled = недопечатан). Так "велосипе" -> mid-word (срезаем
    /// ведущий пробел подсказки), а законченное "привет" -> нет (пробел-разделитель оставляем).
    private static func isMidWord(_ prefix: String) -> Bool {
        guard let last = prefix.last, !WordBoundary.isBoundary(last) else { return false }
        let frag = WordEdit.lastWord(of: prefix)
        guard frag.count >= 2, let lang = SpellLanguage.code(for: frag) else { return false }
        return Speller.isMisspelled(frag, language: lang)
    }

    /// Словарная проверка для склейки стыка (SuggestionJoin.completesFragment):
    /// слово >=2 букв, ru/en, и НЕ помечено опечаткой.
    private static func isDictionaryWord(_ w: String) -> Bool {
        guard w.count >= 2, let lang = SpellLanguage.code(for: w) else { return false }
        return !Speller.isMisspelled(w, language: lang)
    }

    /// Уверенное орфо-исправление слова или nil. Условия: НЕ в личном словаре, слово >=3 букв,
    /// ru/en, помечено опечаткой, у NSSpellChecker есть исправление, отличное от слова И не
    /// являющееся его префиксом (префикс = недопечатанное слово, им занимается автодополнение).
    /// Где применить (мид-слово или после пробела) решает CorrectionPlan.plan - этот хелпер
    /// чисто про «есть ли уверенный fix у данного слова».
    private func spellFix(for word: String) -> String? {
        // Личный словарь (имена/проекты/термины/сленг) - не исправляем, как игнор PuntoSwitcher.
        if CustomDictionary.contains(word, in: customWords) { return nil }
        guard word.count >= 3, let lang = SpellLanguage.code(for: word) else { return nil }
        // Набор русского в английской раскладке ("ghbdtn" -> "привет"): NSSpellChecker "исправит"
        // латиницу в английскую чушь. Если латинское слово конвертится в ВАЛИДНОЕ русское -
        // это mis-layout, а не опечатка: коррекцию не предлагаем, уступаем свитчу раскладки.
        if LayoutAwareCorrection.looksLikeMislayoutRussian(word, isValidRussian: {
            !Speller.isMisspelled($0, language: "ru")
        }) { return nil }
        guard Speller.isMisspelled(word, language: lang),
              let fix = Speller.correction(for: word, language: lang),
              fix.lowercased() != word.lowercased(),
              !fix.lowercased().hasPrefix(word.lowercased()) else { return nil }
        return fix
    }

    /// Показать предложенное исправление зелёным у каретки. Отдельно от showSuggestion, т.к.
    /// это замена слова (isCorrection), а не дописывание.
    private func showCorrection(_ fix: String, ctx: EditingContext) {
        guard let rect = ctx.caretScreenRect else { return }
        let cocoaCaret = DisplayCoordinateConverter.cocoaRect(fromAXRect: rect)
        overlay.show(text: fix, cocoaCaretRect: cocoaCaret, font: font(for: ctx), isCorrection: true)
        onActiveChanged?(true)
    }

    /// Вызывается при смене активности подсказки (появилась / скрылась).
    var onActiveChanged: ((Bool) -> Void)?

    /// Хоткей при непустом выделении: вместо дополнения открываем меню действий
    /// над выделением (UX-03). Wiring в AppDelegate -> SelectionActionController.
    var onSelectionActions: ((EditingContext) -> Void)?

    /// Трансформация текста текущим движком (Selection Actions). Движок приватный и
    /// пересоздаётся при смене модели - наружу отдаём только вызов.
    func transformSelection(_ text: String, action: SelectionAction) async -> String? {
        let e = engine
        return await e.transform(text, action: action)
    }

    /// Бенчмарк ТЕКУЩЕЙ модели (UX-04): короткая генерация на фиксированном префиксе,
    /// метрики скорости для секции «Модель» в настройках. Грузит модель, если ещё не
    /// загружена; сериализуется с генерациями подсказок (общий llama-контекст).
    func benchCurrentModel() async -> BenchTrace? {
        let e = engine
        return try? await e.benchRun(prefix: "Завтра утром я планирую", label: "settings-bench")
    }

    /// Диагностика: исход последнего запроса подсказки (показано/отказано-с-причиной).
    /// Для панели «почему не работает». Не влияет на поведение.
    var onOutcome: ((SuggestionOutcome) -> Void)?

    /// Хранилище событий подсказок (DATA-01). nil при выключенной телеметрии (default-OFF до Phase 4).
    /// Запись только через Task.detached. Гейт на eventStore != nil = гейт телеметрии.
    var eventStore: SuggestionEventStore?
    /// Callback на принятие Tab/Shift+Tab-подсказки (DATA-02). Wiring в AppDelegate -> MemoryKind.accepted.
    var onAcceptedSuggestion: ((_ text: String, _ appBundleId: String?) -> Void)?
    /// Кэш latency последней показанной подсказки (DATA-02/SC-2). firstMs ставится на ПЕРВОМ токене,
    /// totalMs на финале стрима; переиспользуется при .accepted/acceptAll (accept не делает свой замер -
    /// подсказка уже показана); сбрасывается в начале requestSuggestion и в cancelAndHide(), чтобы
    /// accepted не унаследовал latency прошлой подсказки.
    private var lastShownLatencyFirstMs: Int?
    private var lastShownLatencyTotalMs: Int?

    /// Хелпер расчёта миллисекунд из Duration (ContinuousClock).
    private static func ms(_ d: Duration) -> Int {
        let (sec, atto) = d.components
        return Int(sec) * 1000 + Int(atto / 1_000_000_000_000_000)
    }

    /// Записать событие подсказки в фоне. Никогда не на @MainActor write (Pitfall 1: +2-5мс p50).
    /// store == nil (телеметрия выключена) -> ранний выход, ничего не пишем.
    private func recordEvent(outcome: SuggestionEventOutcome, appBundleId: String?,
                             firstMs: Int?, totalMs: Int?, refusal: String? = nil,
                             kind: String? = nil) {
        guard let store = eventStore else { return }
        let event = SuggestionEvent(
            threadKey: appBundleId.map { "\($0):suggest" } ?? "?",
            appBundleId: appBundleId, outcome: outcome.rawValue,
            refusalReason: refusal, latencyFirstMs: firstMs, latencyTotalMs: totalMs,
            modelFile: currentModelFile, promptMode: nil, kind: kind, createdAt: Date())
        Task.detached(priority: .utility) { await store.record(event) }
    }

    /// На каждый EditingContext: reconciler (PERF-02) решает судьбу показанной подсказки -
    /// держать (дубль-контекст), сдвинуть (type-through) или погасить (несовместимость) -
    /// и лишь в последнем случае идём обычным путём (policy + debounce).
    func contextUpdated(_ ctx: EditingContext) {
        switch SuggestionReconcile.decide(
            previousPrefix: latest?.precedingText,
            newPrefix: ctx.precedingText,
            sameApp: latest?.appBundleId == ctx.appBundleId,
            shownSuggestion: enabled ? currentSuggestion : nil) {
        case .unchanged:
            // Дубль-контекст (Electron lag-poll тик / клик в то же место): НЕ гасим ghost и
            // НЕ перезапускаем debounce - раньше именно это мигало. Геометрия могла уточниться.
            latest = ctx
            return
        case .typeThrough(let remaining):
            // Опечатка в только что завершённом слове важнее удержания дополнения:
            // иначе held-ghost маскирует зелёное исправление (репорт: «исправление
            // после пробела» переставало предлагаться).
            if correctionEnabled, ctx.precedingText.last == " ",
               CorrectionPlan.plan(for: ctx.precedingText, spellFix: { self.spellFix(for: $0) }) != nil {
                break   // в invalidated-путь: debounce -> requestSuggestion покажет fix
            }
            // Набрано начало подсказки - сдвигаем ghost без перегенерации
            // (угадываем уже через 1-2 буквы, без моргания).
            latest = ctx
            invalidateStream()
            debounceTask?.cancel(); debounceTask = nil
            currentSuggestion = remaining
            showSuggestion(remaining, ctx: ctx)
            onOutcome?(.completion)
            return
        case .typedThroughAll:
            latest = ctx
            debounceTask?.cancel(); debounceTask = nil
            recordEvent(outcome: .typedThrough, appBundleId: ctx.appBundleId, firstMs: nil, totalMs: nil, kind: "completion")
            cancelAndHide()
            return
        case .invalidated, .noSuggestion:
            // Несовместимость (расхождение/​backspace/смена приложения - SC-2) или подсказки
            // не было: гасим и идём обычным путём. Показывать неверный текст нельзя.
            break
        }
        latest = ctx
        cancelAndHide()
        guard enabled else { onOutcome?(.refused(.disabled)); return }
        switch AutoSuggestPolicy.evaluate(for: ctx, minChars: minChars, excluded: excludedApps) {
        case .refuse(let reason):
            onOutcome?(.refused(reason))
            return
        case .allow:
            break
        }
        // PERF-03: мгновенный кандидат из принятых/памяти - ghost сразу, LLM уточнит
        // параллельно (его первый токен заменит показ; generation ID бережёт от гонок).
        if predictorEnabled, let cand = predictor.predict(after: ctx.precedingText) {
            let shown = SuggestionJoin.normalize(cand, after: ctx.precedingText)
            currentSuggestion = shown
            showSuggestion(shown, ctx: ctx)
            onOutcome?(.completion)
            recordEvent(outcome: .shown, appBundleId: ctx.appBundleId, firstMs: 0, totalMs: 0, kind: "predictor")
        }
        // AX догнал клавиатуру после stale-отказа, нового набора не было - запрашиваем сразу.
        if let typed = staleRetryTyped {
            staleRetryTyped = nil
            if typed == ctx.typedSinceFocus, ContextFreshness.isFresh(ctx) {
                requestSuggestion()
                return
            }
        }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(self.debounceMs))
            if Task.isCancelled { return }
            self.requestSuggestion(auto: true)
        }
    }

    /// Показать подсказку у каретки (позиция/шрифт берутся из контекста).
    private func showSuggestion(_ text: String, ctx: EditingContext) {
        guard let rect = ctx.caretScreenRect else { return }
        let cocoaCaret = DisplayCoordinateConverter.cocoaRect(fromAXRect: rect)
        Self.logCaretGeometry(ctx: ctx, axRect: rect, cocoa: cocoaCaret, font: font(for: ctx))
        overlay.show(text: text, cocoaCaretRect: cocoaCaret, font: font(for: ctx))
        onActiveChanged?(true)
    }

    /// Диагностика геометрии каретки (под DOPISHI_DEBUG_HUD): app + AX-rect + Cocoa-rect + кегль.
    /// Помогает чинить "ghost на строку выше/ниже" в конкретных приложениях (Telegram и т.п.).
    private static func logCaretGeometry(ctx: EditingContext, axRect: CGRect, cocoa: CGRect, font: NSFont) {
        guard ProcessInfo.processInfo.environment["DOPISHI_DEBUG_HUD"] == "1" else { return }
        NSLog("DopishiCaret: app=%@ ax=(%.0f,%.0f %.0fx%.0f) cocoa=(%.0f,%.0f %.0fx%.0f) font=%.1f",
              ctx.appBundleId ?? "-", axRect.minX, axRect.minY, axRect.width, axRect.height,
              cocoa.minX, cocoa.minY, cocoa.width, cocoa.height, font.pointSize)
    }

    /// На .suggestRequested (хоткей или авто после debounce): стримить подсказку у каретки.
    /// При непустом выделении хоткей переключается на действия над выделением (UX-03).
    /// `auto` - запрос пришёл из авто-пути (debounce): только его прореживает adaptive
    /// policy (явный хоткей - просьба пользователя, выполняется всегда).
    func requestSuggestion(auto: Bool = false) {
        guard enabled else { onOutcome?(.refused(.disabled)); return }
        if let ctx = latest, let sel = ctx.selectedText, !sel.isEmpty, !ctx.isSecure,
           AppPolicy.isAllowed(bundleId: ctx.appBundleId, excluded: excludedApps) {
            onSelectionActions?(ctx)
            return
        }
        guard let ctx = latest, ctx.capability == .full, let rect = ctx.caretScreenRect else {
            recordEvent(outcome: .refused, appBundleId: latest?.appBundleId, firstMs: nil, totalMs: nil, refusal: SuggestionRefusal.noCaretGeometry.rawValue)
            onOutcome?(.refused(.noCaretGeometry)); return
        }
        guard !ctx.precedingText.isEmpty else {
            recordEvent(outcome: .refused, appBundleId: ctx.appBundleId, firstMs: nil, totalMs: nil, refusal: SuggestionRefusal.emptyText.rawValue)
            onOutcome?(.refused(.emptyText)); return
        }
        // Freshness-guard: в Electron AX-префикс может отставать от клавиатуры. Генерить по
        // устаревшему префиксу нельзя - подсказка достроит старое состояние ("давай" вместо
        // "давай про"). Если AX отстал от набранного - ждём, пока Electron-поллинг догонит AX
        // и перевызовет requestSuggestion со свежим контекстом.
        guard ContextFreshness.isFresh(ctx) else {
            staleRetryTyped = ctx.typedSinceFocus   // ретрай без debounce, когда AX догонит
            recordEvent(outcome: .refused, appBundleId: ctx.appBundleId, firstMs: nil, totalMs: nil, refusal: SuggestionRefusal.staleContext.rawValue)
            onOutcome?(.refused(.staleContext)); return
        }
        // Каретка в середине текста - ghost лёг бы поверх следующего текста (и в ручном
        // хоткей-пути тоже: рисовать некрасиво независимо от того, кто попросил).
        guard AutoSuggestPolicy.restOfLineIsEmpty(ctx.followingText) else {
            recordEvent(outcome: .refused, appBundleId: ctx.appBundleId, firstMs: nil, totalMs: nil, refusal: SuggestionRefusal.midText.rawValue)
            onOutcome?(.refused(.midText)); return
        }
        // ":имя" - сниппеты и эмодзи (Slack/GitHub-стиль), Tab вставит. Проверяем ПЕРЕД орфо-
        // коррекцией (иначе "sm" из ":sm" ушло бы в спелл-чек). Переиспользуем pendingCorrection
        // (та же семантика «заменить набранный токен на это»). Сниппеты важнее эмодзи (UX-05).
        if let hit = ColonTrigger.token(in: ctx.precedingText) {
            if let text = SnippetCatalog.expansion(name: hit.name, custom: snippets) {
                pendingCorrection = CorrectionPlan.Fix(display: text, insert: text, deleteCount: hit.token.count)
                currentSuggestion = nil
                invalidateStream()
                showCorrection(text, ctx: ctx)
                onOutcome?(.snippet)
                return
            }
            if let emoji = EmojiCatalog.match(name: hit.name) {
                pendingCorrection = CorrectionPlan.Fix(display: emoji, insert: emoji, deleteCount: hit.token.count)
                currentSuggestion = nil
                invalidateStream()
                showCorrection(emoji, ctx: ctx)
                onOutcome?(.emoji)
                return
            }
        }
        // Опечатка -> предлагаем исправление зелёным (вместо авто-замены и вместо LLM-дописывания).
        // CorrectionPlan ловит ДВА случая: слово под кареткой (мид-слово) И только что завершённое
        // слово после пробела (чиним прошлое слово, Tab возвращается и заменяет). Tab применяет план.
        if correctionEnabled, let offer = CorrectionPlan.plan(for: ctx.precedingText, spellFix: { self.spellFix(for: $0) }) {
            pendingCorrection = offer
            currentSuggestion = nil
            task?.cancel(); task = nil
            showCorrection(offer.display, ctx: ctx)
            onOutcome?(.correction)
            return
        }
        pendingCorrection = nil
        // --- Adaptive policy (MEM-02): per-app параметры + прореживание авто-потока ---
        // Блок стоит ПОСЛЕ сниппетов/коррекций: политика касается только LLM-генерации.
        var adaptiveForRequest: AdaptiveParams? = nil
        if let provider = adaptiveParamsProvider {
            let global = AdaptiveParams(minConfidence: EngineConfig.production.minConfidence,
                                        maxWords: maxWordsGlobal, showRate: 1.0)
            let appKey = ctx.appBundleId ?? "-"
            let idx = adaptiveRequestIndex[appKey, default: 0]
            adaptiveRequestIndex[appKey] = idx + 1
            let adaptive = provider(ctx.appBundleId, global)
            if auto, !AdaptivePolicy.admits(requestIndex: idx, showRate: adaptive.showRate) {
                // Прорежено политикой (низкое принятие в приложении): тихий skip авто-запроса.
                // Floor 0.3 + explore-такты гарантируют, что поток не молчит насовсем.
                return
            }
            adaptiveForRequest = AdaptivePolicy.paramsForRequest(index: idx, adaptive: adaptive,
                                                                 global: global)
        }
        let cocoaCaret = DisplayCoordinateConverter.cocoaRect(fromAXRect: rect)
        Self.logCaretGeometry(ctx: ctx, axRect: rect, cocoa: cocoaCaret, font: font(for: ctx))
        let prefix = ctx.precedingText
        let appId = ctx.appBundleId
        // mid-word: дописываем НЕЗАКОНЧЕННОЕ слово -> ведущий пробел подсказки лишний. По контексту
        // "велосипе"(mid) и "привет"(законч.) неразличимы -> словарём: незаконченное = misspelled.
        let midWord = Self.isMidWord(prefix)
        // PERF-04: адаптивный бюджет хвоста - мид-слово короче, конец мысли полнее.
        // KV-safe: статическая голова промпта не меняется, варьируется только хвост.
        let budget = PromptBudget.tailMax(prefix: prefix, isMidWord: midWord)
        // OCR/буфер-каналы (если фичи вкл и есть данные) - подмешиваются в промпт через ContextBuilder.
        let bundle = ContextBundle(fieldTail: String(prefix.suffix(budget)), ocr: ctx.ocr, clipboard: ctx.clipboard, memory: ctx.memory)
        let font = self.font(for: ctx)
        let requestStart = ContinuousClock.now           // замер до task = Task
        let capturedAppId = appId                         // захват для записи из Task
        // Сброс кэша на старте нового запроса (не наследуем latency прошлой подсказки).
        lastShownLatencyFirstMs = nil
        lastShownLatencyTotalMs = nil
        task?.cancel()
        generation += 1
        let gen = generation
        task = Task { [weak self] in
            guard let self else { return }
            var shown = false
            var firstTokenTime: ContinuousClock.Instant? = nil
            do {
                for try await suggestion in await self.engine.stream(bundle: bundle, appId: appId,
                                                                     adaptive: adaptiveForRequest) {
                    // Поколение: устаревший стрим не должен рисовать поверх нового состояния
                    // (Task.cancel асинхронный - флага может ещё не быть, gen уже сменился).
                    if Task.isCancelled || gen != self.generation { break }
                    if firstTokenTime == nil {
                        firstTokenTime = ContinuousClock.now
                        // firstMs кэшируем СРАЗУ на первом токене (mid-stream Tab возьмёт его).
                        self.lastShownLatencyFirstMs = Self.ms(ContinuousClock.now - requestStart)
                    }
                    if !shown { self.onOutcome?(.completion) }
                    shown = true
                    // Срезаем дублирующий пробел на стыке (модель часто даёт подсказку с
                    // ведущим пробелом, а контекст уже может кончаться пробелом). Нормализуем
                    // до показа, чтобы ghost-превью и вставка по Tab совпадали.
                    // completesFragment: фрагмент-валидное-слово ("при" + " ложение"), где
                    // misspelled-эвристика isMidWord промахивается и пробел ушёл бы во вставку.
                    let joined = SuggestionJoin.normalize(
                        suggestion, after: prefix,
                        midWord: midWord || SuggestionJoin.completesFragment(
                            suggestion, after: prefix, isValidWord: Self.isDictionaryWord))
                    self.currentSuggestion = joined
                    self.overlay.show(text: joined, cocoaCaretRect: cocoaCaret, font: font)
                    self.onActiveChanged?(true)
                }
                // Отменён новым запросом (быстрый набор/accept/dismiss) - записываем shown из
                // локальных значений если подсказка уже была показана, затем тихо выходим.
                if Task.isCancelled || gen != self.generation {
                    if shown, let store = self.eventStore {
                        let firstMs = firstTokenTime.map { Self.ms($0 - requestStart) }
                        let totalMs = Self.ms(ContinuousClock.now - requestStart)
                        let ev = SuggestionEvent(
                            threadKey: capturedAppId.map { "\($0):suggest" } ?? "?",
                            appBundleId: capturedAppId, outcome: SuggestionEventOutcome.shown.rawValue,
                            refusalReason: nil, latencyFirstMs: firstMs, latencyTotalMs: totalMs,
                            modelFile: self.currentModelFile, promptMode: nil, kind: "completion", createdAt: Date())
                        Task.detached(priority: .utility) { await store.record(ev) }
                    }
                    return
                }
                let endTime = ContinuousClock.now
                let firstMs = firstTokenTime.map { Self.ms($0 - requestStart) }
                let totalMs = Self.ms(endTime - requestStart)
                if shown {
                    // totalMs кэшируем на финале (firstMs уже закэширован на первом токене).
                    self.lastShownLatencyTotalMs = totalMs
                    self.recordEvent(outcome: .shown, appBundleId: capturedAppId, firstMs: firstMs, totalMs: totalMs, kind: "completion")
                } else {
                    // SC-5 (Phase 6): причина движкового отказа (lowConfidence/repetition/
                    // languageMismatch/...) уходит в suggestion_event. recordOutcome движка
                    // выполняется ДО finish() стрима - здесь причина уже актуальна.
                    let engineReason = await self.engine.lastRejectionReason()
                    self.recordEvent(outcome: .modelEmpty, appBundleId: capturedAppId,
                                     firstMs: nil, totalMs: nil,
                                     refusal: engineReason == .none ? nil : engineReason.rawValue,
                                     kind: "completion")
                    // Гасим только если мы всё ещё текущее поколение - устаревший пустой стрим
                    // не должен погасить подсказку, показанную более новым запросом.
                    if gen == self.generation { self.cancelAndHide() }
                    self.onOutcome?(.modelEmpty)
                }
            } catch {
                if Task.isCancelled || gen != self.generation { return }
                NSLog("SuggestionController: \(error)")
                // Не оставляем залипший ghost и suggestionActive=true (иначе Tab продолжит
                // поглощаться без подсказки).
                self.cancelAndHide()
            }
        }
    }

    /// Tab: вставить ОДНО слово показанной подсказки. Остаток фразы НЕ теряем (хвост из памяти):
    /// latest сдвигаем на пост-вставку, остаток кладём в currentSuggestion. На следующем наборе
    /// существующий type-through продолжит ИМЕННО эту фразу, а не сгенерит другую.
    func accept() {
        // Предложенное исправление/эмодзи: Tab применяет план (удаляем deleteCount символов
        // назад - слово, опц. хвостовой пробел или ":name" - и вставляем insert).
        if let c = pendingCorrection {
            Injector.replaceLastWord(deleteCount: c.deleteCount, with: c.insert)
            cancelAndHide()
            return
        }
        guard let s = currentSuggestion, !s.isEmpty else { return }
        let chunk = WordAccept.firstChunk(of: s)
        // --- DATA-02: callback + запись accepted с latency из кэша shown ---
        // WR-04: принятый текст уходит в персистентную память (контракт MemoryProvider.record:
        // только allowed + non-secure). Хоткей-путь, в отличие от авто-пути, secure/excluded
        // не гейтит - проверяем здесь; без контекста (latest == nil) fail-closed, не пишем.
        if let ctx = latest, AppPolicy.allowsMemoryWrite(isSecure: ctx.isSecure,
                                                         bundleId: ctx.appBundleId,
                                                         excluded: excludedApps,
                                                         learningExcluded: memoryExcludedApps) {
            onAcceptedSuggestion?(chunk, ctx.appBundleId)
        }
        // Один accepted на подсказку: кэш latency непуст ровно до первого Tab. Повторные Tab
        // той же фразы (пословное принятие) событие НЕ пишут - иначе одна shown давала бы
        // N accepted и acceptance rate (accepted/shown) завышался бы в разы.
        if lastShownLatencyFirstMs != nil {
            recordEvent(outcome: .accepted, appBundleId: latest?.appBundleId,
                        firstMs: lastShownLatencyFirstMs, totalMs: lastShownLatencyTotalMs, kind: "completion")
        }
        lastShownLatencyFirstMs = nil
        lastShownLatencyTotalMs = nil
        // --- конец вставки; ниже существующие строки ---
        let remaining = String(s.dropFirst(chunk.count))
        Injector.insert(chunk)
        guard !remaining.isEmpty else { cancelAndHide(); return }
        invalidateStream()
        debounceTask?.cancel(); debounceTask = nil
        if let l = latest { latest = l.withPrecedingText(l.precedingText + chunk) }
        currentSuggestion = remaining
        overlay.hide()            // покажем остаток у новой каретки на следующем наборе (type-through)
        onActiveChanged?(false)
    }

    /// Клавиша над Tab (grave): вставить ВСЮ показанную подсказку целиком и скрыть.
    /// Многословную фразу так принимают одной вставкой, без N round-trip'ов к модели.
    func acceptAll() {
        guard let s = currentSuggestion, !s.isEmpty else { return }
        // WR-04: тот же secure/excluded-гейт записи в память, что в accept().
        if let ctx = latest, AppPolicy.allowsMemoryWrite(isSecure: ctx.isSecure,
                                                         bundleId: ctx.appBundleId,
                                                         excluded: excludedApps,
                                                         learningExcluded: memoryExcludedApps) {
            onAcceptedSuggestion?(s, ctx.appBundleId)
        }
        // Один accepted на подсказку (см. accept): grave после Tab той же фразы не пишет повторно.
        if lastShownLatencyFirstMs != nil {
            recordEvent(outcome: .accepted, appBundleId: latest?.appBundleId,
                        firstMs: lastShownLatencyFirstMs, totalMs: lastShownLatencyTotalMs, kind: "completion")
        }
        Injector.insert(s)
        cancelAndHide()
    }

    /// После Tab/grave probe перечитал новую каретку/текст. Если в памяти остался хвост
    /// многословной фразы (tail-from-memory) - показываем его сразу у новой каретки (без
    /// генерации); иначе генерим следующее слово, не дожидаясь набора. Так продолжение видно
    /// мгновенно после принятия слова, а не только когда пользователь начнёт печатать.
    func continueAfterAccept(_ ctx: EditingContext) {
        guard enabled else { return }
        latest = ctx
        guard AutoSuggestPolicy.shouldSuggest(for: ctx, minChars: minChars, excluded: excludedApps) else {
            cancelAndHide(); return
        }
        if let s = currentSuggestion, !s.isEmpty, ctx.caretScreenRect != nil {
            showSuggestion(s, ctx: ctx)
        } else {
            requestSuggestion()
        }
    }

    /// Esc: скрыть подсказку. Если была активная LLM-подсказка - пишет dismissed (DATA-01).
    func dismiss() {
        if currentSuggestion != nil {
            recordEvent(outcome: .dismissed, appBundleId: latest?.appBundleId, firstMs: nil, totalMs: nil, kind: "completion")
        }
        cancelAndHide()
    }

    /// Спрятать подсказку при потере фокуса (смена активного приложения). Без записи dismissed -
    /// это не сознательный отказ пользователя, а уход фокуса (F5: didActivateApplication-путь).
    func hideOnFocusLoss() {
        cancelAndHide()
    }

    /// Отменить летящий стрим и инвалидировать его поколение: даже если Task.cancel ещё не
    /// дошёл до стрима, его show() больше не пройдёт gen-guard.
    private func invalidateStream() {
        task?.cancel()
        task = nil
        generation += 1
    }

    func cancelAndHide() {
        invalidateStream()
        debounceTask?.cancel()
        debounceTask = nil
        currentSuggestion = nil
        pendingCorrection = nil
        lastShownLatencyFirstMs = nil
        lastShownLatencyTotalMs = nil
        overlay.hide()
        onActiveChanged?(false)
    }
}
