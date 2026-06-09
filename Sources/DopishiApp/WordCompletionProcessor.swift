import AppKit
import DopishiCore

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
            if tryLayout(word: word, boundary: bnd, candidate: KeyboardLayout.enToRussian(word), candLang: "ru", switchTo: "ru") { return true }
            if tryLayout(word: word, boundary: bnd, candidate: KeyboardLayout.ruToEnglish(word), candLang: "en", switchTo: "en") { return true }
        }
        // Автоисправление орфографии БОЛЬШЕ НЕ подменяет слово на границе. Исправление теперь
        // ПРЕДЛАГАЕТСЯ зелёным призраком по ходу набора (SuggestionController + TypoCorrection),
        // принимается Tab - модель Cotabby/Cotypist. Здесь остаётся только раскладка.
        return false
    }

    /// Ручное переключение раскладки по тапу Option (Punto-стиль), конвертирует БЕЗУСЛОВНО.
    /// Если есть выделение - конвертирует весь выделенный текст (вставка заменяет выделение),
    /// иначе - последнее слово до каретки. precedingText - текст до каретки без границы.
    func manualLayoutSwitch(precedingText text: String, selectedText: String?) {
        guard manualLayoutEnabled else { return }
        // Антидребезг: повторный тап в течение 250 мс игнорируем (инъекция ещё в полёте).
        let now = Date()
        if let last = lastManualSwitchAt, now.timeIntervalSince(last) < 0.25 { return }

        // Есть выделение - конвертируем целиком и ЗАМЕНЯЕМ выделенный текст
        // (удаляем выделение Backspace-ом, затем вставляем - иначе текст добавился бы рядом).
        if let sel = selectedText, !sel.isEmpty {
            guard let (replacement, lang) = ManualLayout.convert(sel) else { return }
            lastManualSwitchAt = now
            Injector.replaceSelection(with: replacement)
            LayoutSwitcher.selectLayout(language: lang)
            lastEdit = (deleteCount: replacement.count, restore: sel)
            return
        }

        // Иначе - последний токен до каретки (по пробелам, с пунктуацией внутри - чтобы
        // "ghbdtn,vbh" конвертировалось целиком). Хвостовой пробел учитываем: если юзер уже
        // поставил пробел после слова ("ghbdtn "), конвертим слово и пробел сохраняем.
        let (word, trailing) = WordEdit.lastSpaceTokenWithTrailing(of: text)
        guard !word.isEmpty, let (replacement, lang) = ManualLayout.convert(word) else { return }
        lastManualSwitchAt = now
        replace(word: word, boundary: trailing, with: replacement)
        LayoutSwitcher.selectLayout(language: lang)
    }

    private func tryLayout(word: String, boundary: String, candidate: String, candLang: String, switchTo: String) -> Bool {
        guard candidate != word else { return false }
        let typedLang = looksCyrillic(word) ? "ru" : "en"
        let typedIsWord = !Speller.isMisspelled(word, language: typedLang)
        let candIsWord = !Speller.isMisspelled(candidate, language: candLang)
        guard LayoutDecision.shouldSwitch(asTypedIsWord: typedIsWord, transliteratedIsWord: candIsWord) else { return false }
        replace(word: word, boundary: boundary, with: candidate)
        LayoutSwitcher.selectLayout(language: switchTo)
        return true
    }

    /// ВАЖНО: deleteCount трактуется как число Backspace (1 графема = 1 Backspace).
    /// Корректно для ru/en (1 символ = 1 скаляр); если KeyboardLayout получит
    /// многоскалярные маппинги - откат рассинхронизируется, пересмотреть подсчёт.
    /// Удалить слово + граничный символ и вставить замену + ту же границу.
    private func replace(word: String, boundary: String, with replacement: String) {
        let inserted = replacement + boundary
        Injector.replaceLastWord(deleteCount: word.count + boundary.count, with: inserted)
        lastEdit = (deleteCount: inserted.count, restore: word + boundary)
    }

    /// Откат последней авто-замены (⌃⌥Z).
    func undoLast() {
        guard let e = lastEdit else { return }
        Injector.replaceLastWord(deleteCount: e.deleteCount, with: e.restore)
        lastEdit = nil
    }

    private func looksCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}
