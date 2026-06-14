import AppKit
import DopishiCore
import IOKit.hidsystem

/// На завершении слова применяет автопереключение раскладки и автоисправление орфографии.
/// Хранит последнюю замену для отката (⌃⌥Z). Работает только если включён соответствующий тумблер.
@MainActor
final class WordCompletionProcessor {
    var layoutEnabled = false
    var autocorrectEnabled = false
    var manualLayoutEnabled = false

    /// Время последней ручной замены - защита от повторного тапа до того,
    /// как инъекция первого долетит до поля (иначе второй тап прочитает устаревший AX-текст).
    private var lastManualSwitchAt: Date?

    /// (сколько удалить, что вставить для отката) последней авто-замены.
    private(set) var lastEdit: (deleteCount: Int, restore: String)?

    /// precedingText - текст до каретки, ВКЛЮЧАЯ только что набранный граничный символ
    /// (напр. "ghbdtn "). Каретка в конце.
    /// Возвращает true, если была инъекция (замена слова) - вызывающий сбросит
    /// клавиатурный буфер, иначе он рассинхронится с AX и freshness-guard заблокирует подсказки.
    @discardableResult
    func wordCompleted(precedingText text: String) -> Bool {
        // Только раскладка: автоисправление переехало в предложение-призрак (см. wordCompleted-док).
        guard layoutEnabled else { return false }
        guard let boundary = text.last, WordBoundary.isBoundary(boundary) else { return false }
        let word = WordEdit.lastWord(of: text)
        guard word.count >= 2 else { return false }
        let bnd = String(boundary)

        if layoutEnabled {
            // Сначала целый спейс-токен: слова с б/ю в EN-раскладке ("будет"=",eltn",
            // "любой"="k.,jq") содержат , и . - lastWord рвёт их на границах, и простой
            // путь такое слово не видит вовсе (репорт: "запятые и точки остаются").
            if tryTokenLayout(text: text, boundary: bnd) { return true }
            if tryLayout(word: word, boundary: bnd, candidate: KeyboardLayout.enToRussian(word), candLang: "ru", switchTo: "ru") { return true }
            if tryLayout(word: word, boundary: bnd, candidate: KeyboardLayout.ruToEnglish(word), candLang: "en", switchTo: "en") { return true }
            // Забытый CapsLock: "пРИВЕТ " -> "Привет " + выключаем сам капс. Гейт по реальному
            // состоянию CapsLock - паттерн без включённого капса (странный ручной регистр) не трогаем.
            if Self.capsLockIsOn, let fixed = CapsFix.fix(word) {
                Self.layoutLog("caps: '\(word)' -> '\(fixed)'")
                replace(word: word, boundary: bnd, deleting: word.count + bnd.count, with: fixed)
                Self.setCapsLock(false)
                return true
            }
        }
        // Автоисправление орфографии БОЛЬШЕ НЕ подменяет слово на границе. Исправление теперь
        // ПРЕДЛАГАЕТСЯ зелёным призраком по ходу набора (SuggestionController + TypoCorrection),
        // принимается Tab - модель Cotabby/Cotypist. Здесь остаётся только раскладка.
        return false
    }

    nonisolated static let layoutDebug = ProcessInfo.processInfo.environment["DOPISHI_LAYOUT_DEBUG"] == "1"
    nonisolated static func layoutLog(_ s: @autoclosure () -> String) {
        if layoutDebug { NSLog("DopishiLayout: %@", s()) }
    }

    /// Ручное переключение раскладки по тапу Option (Punto-стиль), конвертирует БЕЗУСЛОВНО.
    /// Если есть выделение - конвертирует весь выделенный текст (вставка заменяет выделение),
    /// иначе - последнее слово до каретки. Явный жест -> minLength 1 (конвертим и одиночные предлоги).
    func manualLayoutSwitch(precedingText text: String, selectedText: String?) {
        guard manualLayoutEnabled else { return }
        // Антидребезг: повторный тап в течение 250 мс игнорируем (инъекция ещё в полёте).
        let now = Date()
        if let last = lastManualSwitchAt, now.timeIntervalSince(last) < 0.25 { return }
        Self.layoutLog("tap: sel='\(selectedText ?? "nil")' tail='\(text.suffix(24))'")

        // Есть выделение - конвертируем целиком и ЗАМЕНЯЕМ выделенный текст
        // (удаляем выделение Backspace-ом, затем вставляем - иначе текст добавился бы рядом).
        if let sel = selectedText, !sel.isEmpty {
            guard let (replacement, lang) = ManualLayout.convert(sel, minLength: 1) else {
                Self.layoutLog("selection: convert nil для '\(sel)'"); return
            }
            lastManualSwitchAt = now
            Self.layoutLog("selection: '\(sel)' -> '\(replacement)' (\(lang))")
            Injector.replaceSelection(with: replacement)
            LayoutSwitcher.selectLayout(language: lang)
            lastEdit = (deleteCount: replacement.count, restore: sel)
            return
        }

        // Иначе - последний токен до каретки (по пробелам, с пунктуацией внутри - чтобы
        // "ghbdtn,vbh" конвертировалось целиком). Хвостовой пробел учитываем: если юзер уже
        // поставил пробел после слова ("ghbdtn "), конвертим слово и пробел сохраняем.
        let (word, trailing) = WordEdit.lastSpaceTokenWithTrailing(of: text)
        guard !word.isEmpty, let (replacement, lang) = ManualLayout.convert(word, minLength: 1) else {
            Self.layoutLog("word: нечего конвертировать (word='\(word)')"); return
        }
        lastManualSwitchAt = now
        Self.layoutLog("word: '\(word)' -> '\(replacement)' (\(lang))")
        replace(word: word, boundary: trailing, deleting: word.count + trailing.count, with: replacement)
        LayoutSwitcher.selectLayout(language: lang)
    }

    private func tryLayout(word: String, boundary: String, candidate: String, candLang: String, switchTo: String) -> Bool {
        guard candidate != word else { return false }
        let typedLang = looksCyrillic(word) ? "ru" : "en"
        let typedIsWord = !Speller.isMisspelled(word, language: typedLang)
        let candIsWord = !Speller.isMisspelled(candidate, language: candLang)
        guard LayoutDecision.shouldSwitch(asTypedIsWord: typedIsWord, transliteratedIsWord: candIsWord) else { return false }
        replace(word: word, boundary: convertBoundary(boundary, to: switchTo), deleting: word.count + boundary.count, with: candidate)
        LayoutSwitcher.selectLayout(language: switchTo)
        return true
    }

    /// Целый спейс-токен с пунктуацией внутри: "k.,jq" -> "любой". Гейты: кандидат целиком
    /// буквенный (пунктуация смаппилась в б/ю/ё) и словарный - иначе не трогаем.
    private func tryTokenLayout(text: String, boundary: String) -> Bool {
        let body = String(text.dropLast(boundary.count))
        let (token, _) = WordEdit.lastSpaceTokenWithTrailing(of: body)
        // Без пунктуации внутри токен совпадает с lastWord - этим займётся простой путь.
        guard token.count >= 2, token != WordEdit.lastWord(of: body) else { return false }
        guard let (candidate, lang) = ManualLayout.convert(token, minLength: 2) else { return false }
        guard candidate.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }
        guard !Speller.isMisspelled(candidate, language: lang) else { return false }
        Self.layoutLog("token: '\(token)' -> '\(candidate)' (\(lang))")
        replace(word: token, boundary: convertBoundary(boundary, to: lang), deleting: token.count + boundary.count, with: candidate)
        LayoutSwitcher.selectLayout(language: lang)
        return true
    }

    /// Граничный символ конвертируется вместе со словом: "/"->"." и "?"->"," при свитче
    /// в ru - иначе "ghbdtn/" давал "привет/" (точка оставалась слэшем). Пробел не в карте.
    private func convertBoundary(_ b: String, to lang: String) -> String {
        lang == "ru" ? KeyboardLayout.enToRussian(b) : KeyboardLayout.ruToEnglish(b)
    }

    /// ВАЖНО: deleteCount трактуется как число Backspace (1 графема = 1 Backspace).
    /// Корректно для ru/en (1 символ = 1 скаляр); если KeyboardLayout получит
    /// многоскалярные маппинги - откат рассинхронизируется, пересмотреть подсчёт.
    /// Удалить слово + граничный символ и вставить замену + ту же границу.
    private func replace(word: String, boundary: String, deleting deleteCount: Int, with replacement: String) {
        let inserted = replacement + boundary
        Injector.replaceLastWord(deleteCount: deleteCount, with: inserted)
        lastEdit = (deleteCount: inserted.count, restore: word + boundary)
    }

    /// Откат последней авто-замены (⌃⌥Z).
    func undoLast() {
        guard let e = lastEdit else { return }
        Injector.replaceLastWord(deleteCount: e.deleteCount, with: e.restore)
        lastEdit = nil
    }

    /// Текущее состояние CapsLock (из HID-состояния системы).
    private static var capsLockIsOn: Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }

    /// Программно выключить CapsLock (IOKit HID) - как PuntoSwitcher после исправления.
    private static func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), on)
    }

    private func looksCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}
