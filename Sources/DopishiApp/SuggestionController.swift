import AppKit
import DopishiCore
import DopishiLLM

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
    private var enabled = true
    private var debounceMs = 350
    private var minChars = 3
    private var excludedApps: Set<String> = []
    /// Предлагать ли исправление опечатки (вместо старой авто-замены). Тумблер autocorrect.
    private var correctionEnabled = true
    /// Текущее предложенное исправление текущего слова: (опечатка, исправление). Показывается
    /// зелёным; Tab заменяет опечатку на fix. Держим ОТДЕЛЬНО от currentSuggestion, чтобы
    /// type-through (продолжение фразы) не путал коррекцию с дописыванием.
    private var pendingCorrection: (typo: String, fix: String)?

    private var currentModelFile = ModelCatalog.defaultFileName

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
        correctionEnabled = s.autocorrectEnabled   // тумблер теперь = «предлагать исправление»
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

    /// Исправление текущего слова для предложения (Cotabby-модель). Условия: фича вкл, мы СЕРЕДИНЕ
    /// слова (префикс не кончается границей), слово >=3 букв, оно misspelled и у словаря есть
    /// исправление, отличное от набранного. НЕ предлагаем, если опечатка - просто префикс
    /// исправления (это недопечатанное слово - им занимается автодополнение, не орфо-фикс).
    private static func correctionOffer(for prefix: String, enabled: Bool) -> (typo: String, fix: String)? {
        guard enabled, let last = prefix.last, !WordBoundary.isBoundary(last) else { return nil }
        let word = WordEdit.lastWord(of: prefix)
        guard word.count >= 3, let lang = SpellLanguage.code(for: word) else { return nil }
        guard Speller.isMisspelled(word, language: lang),
              let fix = Speller.correction(for: word, language: lang),
              fix.lowercased() != word.lowercased(),
              !fix.lowercased().hasPrefix(word.lowercased()) else { return nil }
        return (word, fix)
    }

    /// Эмодзи-предложение: последнее ":" с именем (буквы/цифры/_) после него, без пробела. ":"
    /// в начале или после пробела (чтобы не триггерить "http://", "10:30"). token = ":name" -
    /// его и заменяем на эмодзи. nil если совпадения нет.
    private static func emojiOffer(for prefix: String) -> (token: String, emoji: String)? {
        guard let colonIdx = prefix.lastIndex(of: ":") else { return nil }
        let after = prefix[prefix.index(after: colonIdx)...]
        guard !after.isEmpty,
              after.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        if colonIdx > prefix.startIndex {
            let before = prefix[prefix.index(before: colonIdx)]
            guard before == " " || before == "\n" || before == "\t" else { return nil }
        }
        let name = String(after)
        guard let emoji = EmojiCatalog.match(name: name) else { return nil }
        return (token: ":" + name, emoji: emoji)
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

    /// На каждый EditingContext: отменить текущее и (если уместно) запланировать
    /// автоподсказку после паузы в наборе.
    func contextUpdated(_ ctx: EditingContext) {
        // Type-through: пользователь набрал начало показанной подсказки - сдвигаем ghost
        // без перегенерации (как Cotypist: "угадывает уже через 1-2 буквы", без моргания).
        if enabled, let prev = latest, let sug = currentSuggestion, !sug.isEmpty,
           ctx.precedingText.count > prev.precedingText.count,
           ctx.precedingText.hasPrefix(prev.precedingText) {
            let typed = String(ctx.precedingText.dropFirst(prev.precedingText.count))
            if !typed.isEmpty, sug.hasPrefix(typed) {
                latest = ctx
                task?.cancel(); task = nil
                debounceTask?.cancel(); debounceTask = nil
                let remaining = String(sug.dropFirst(typed.count))
                if remaining.isEmpty {
                    cancelAndHide()
                } else {
                    currentSuggestion = remaining
                    showSuggestion(remaining, ctx: ctx)
                }
                return
            }
        }
        latest = ctx
        cancelAndHide()
        guard enabled, AutoSuggestPolicy.shouldSuggest(for: ctx, minChars: minChars, excluded: excludedApps) else { return }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(self.debounceMs))
            if Task.isCancelled { return }
            self.requestSuggestion()
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

    /// На .suggestRequested (хоткей): стримить подсказку у каретки.
    func requestSuggestion() {
        guard enabled else { return }
        guard let ctx = latest, ctx.capability == .full,
              let rect = ctx.caretScreenRect,
              !ctx.precedingText.isEmpty else {
            return
        }
        // Freshness-guard: в Electron AX-префикс может отставать от клавиатуры. Генерить по
        // устаревшему префиксу нельзя - подсказка достроит старое состояние ("давай" вместо
        // "давай про"). Если AX отстал от набранного - ждём, пока Electron-поллинг догонит AX
        // и перевызовет requestSuggestion со свежим контекстом.
        guard ContextFreshness.isFresh(ctx) else { return }
        // Эмодзи: ":name" -> эмодзи (Slack/GitHub-стиль), Tab вставит. Проверяем ПЕРЕД орфо-
        // коррекцией (иначе "sm" из ":sm" ушло бы в спелл-чек). Переиспользуем pendingCorrection
        // (та же семантика «заменить набранный токен на это»).
        if let emoji = Self.emojiOffer(for: ctx.precedingText) {
            pendingCorrection = (typo: emoji.token, fix: emoji.emoji)
            currentSuggestion = nil
            task?.cancel(); task = nil
            showCorrection(emoji.emoji, ctx: ctx)
            return
        }
        // Опечатка текущего слова -> предлагаем исправление зелёным (вместо авто-замены и вместо
        // LLM-дописывания). Tab заменит слово. Модель Cotabby «Offer Corrections on Typo».
        if let offer = Self.correctionOffer(for: ctx.precedingText, enabled: correctionEnabled) {
            pendingCorrection = offer
            currentSuggestion = nil
            task?.cancel(); task = nil
            showCorrection(offer.fix, ctx: ctx)
            return
        }
        pendingCorrection = nil
        let cocoaCaret = DisplayCoordinateConverter.cocoaRect(fromAXRect: rect)
        Self.logCaretGeometry(ctx: ctx, axRect: rect, cocoa: cocoaCaret, font: font(for: ctx))
        let prefix = ctx.precedingText
        let appId = ctx.appBundleId
        // mid-word: дописываем НЕЗАКОНЧЕННОЕ слово -> ведущий пробел подсказки лишний. По контексту
        // "велосипе"(mid) и "привет"(законч.) неразличимы -> словарём: незаконченное = misspelled.
        let midWord = Self.isMidWord(prefix)
        // OCR/буфер-каналы (если фичи вкл и есть данные) - подмешиваются в промпт через ContextBuilder.
        let bundle = ContextBundle(fieldTail: prefix, ocr: ctx.ocr, clipboard: ctx.clipboard, memory: ctx.memory)
        let font = self.font(for: ctx)
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            var shown = false
            do {
                for try await suggestion in await self.engine.stream(bundle: bundle, appId: appId) {
                    if Task.isCancelled { break }
                    shown = true
                    // Срезаем дублирующий пробел на стыке (модель часто даёт подсказку с
                    // ведущим пробелом, а контекст уже может кончаться пробелом). Нормализуем
                    // до показа, чтобы ghost-превью и вставка по Tab совпадали.
                    let joined = SuggestionJoin.normalize(suggestion, after: prefix, midWord: midWord)
                    self.currentSuggestion = joined
                    self.overlay.show(text: joined, cocoaCaretRect: cocoaCaret, font: font)
                    self.onActiveChanged?(true)
                }
                if !shown { self.cancelAndHide() }
            } catch {
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
        // Предложенное исправление опечатки: Tab заменяет текущее слово на fix (удаляем
        // набранные символы опечатки + вставляем исправление).
        if let c = pendingCorrection {
            Injector.replaceLastWord(deleteCount: c.typo.count, with: c.fix)
            cancelAndHide()
            return
        }
        guard let s = currentSuggestion, !s.isEmpty else { return }
        let chunk = WordAccept.firstChunk(of: s)
        let remaining = String(s.dropFirst(chunk.count))
        Injector.insert(chunk)
        guard !remaining.isEmpty else { cancelAndHide(); return }
        task?.cancel(); task = nil
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

    /// Esc: просто скрыть.
    func dismiss() {
        cancelAndHide()
    }

    func cancelAndHide() {
        task?.cancel()
        task = nil
        debounceTask?.cancel()
        debounceTask = nil
        currentSuggestion = nil
        pendingCorrection = nil
        overlay.hide()
        onActiveChanged?(false)
    }
}
