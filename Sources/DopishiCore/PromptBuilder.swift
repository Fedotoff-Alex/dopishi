import Foundation

public enum PromptBuilder {
    /// Prompt для продолжения: недавний текст до каретки, обрезанный хвостом до maxChars.
    /// Хвостовые пробелы/переводы строк обрезаются: прямой прогон показал, что с trailing-пробелом
    /// модель даёт мусор ("2-й язык"), а без него - осмысленно ("русский язык"). Двойные пробелы
    /// на стыке всё равно чистятся в SuggestionJoin.normalize.
    public static func completionPrompt(from precedingText: String, maxChars: Int = 1200) -> String {
        var tail = precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
        while let last = tail.last, last == " " || last == "\n" || last == "\t" { tail.removeLast() }
        return tail
    }

    /// Статический few-shot префикс (без chat-тегов). Задаёт формат "короткое осмысленное
    /// продолжение тем же языком". Голый continuation на Gemma уезжал в чужую длинную историю
    /// ("Thank you for your" -> "feedback. I've checked your issue..."); few-shot даёт
    /// "Thank you for your" -> "help" (прямой DIAG-прогон на той же модели). Префикс статичен -
    /// переиспользуется KV prefix-reuse, декодируется только динамический хвост.
    public static let fewShotPrefix = """
    Продолжи каждый текст естественным коротким продолжением тем же языком.

    Текст: Сегодня прекрасная
    Продолжение: погода для прогулки

    Текст: I would really like to
    Продолжение: thank you for your help

    Текст:
    """

    /// Тот же few-shot префикс, но БЕЗ финального "Текст:" - чтобы перед ним вставить секцию
    /// "Окно: <ocr>" (ContextBuilder), сохранив статическую KV-голову. Выводится из fewShotPrefix,
    /// чтобы не дублировать литерал few-shot.
    public static var fewShotPrefixWithoutLastTextLabel: String {
        String(fewShotPrefix.dropLast("Текст:".count))
    }

    /// Few-shot промпт продолжения: статический префикс + недавний текст + "Продолжение:".
    /// Стоп по первому \n (CompletionStop) отрезает шаблонный хвост "\n\nТекст: ...".
    public static func fewShotCompletionPrompt(from precedingText: String, maxChars: Int = 600) -> String {
        var tail = precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
        while let last = tail.last, last == " " || last == "\n" || last == "\t" { tail.removeLast() }
        return fewShotPrefix + " " + tail + "\nПродолжение:"
    }

    /// Режимы построения промпта для A/B-бенча и per-model настройки.
    public enum Mode: String, Sendable, CaseIterable, Codable {
        case fewShot        // статический few-shot префикс (дефолт продакшна)
        case plainTrimmed   // голый хвост, trailing-WS обрезан (старый дефолт)
        case plainRaw       // голый хвост, trailing-WS СОХРАНЁН (бриф просит проверить)
        case minimalInline  // одна строка-инструкция + текст
        case gemmaChat      // chat-turns Gemma (A/B, обычно пусто из-за \n-EOS)
    }

    /// Единая точка построения промпта по режиму - для бенча и движка. instructions - опц.
    /// пользовательские указания, идут в СТАТИЧЕСКУЮ голову (KV-голова цела), пусто -> ничего.
    public static func build(mode: Mode, from precedingText: String, modelFileName: String = "",
                             instructions: String = "") -> String {
        let body: String
        switch mode {
        case .fewShot:       body = fewShotCompletionPrompt(from: precedingText)
        case .plainTrimmed:  body = completionPrompt(from: precedingText)
        case .plainRaw:      body = plainRawPrompt(from: precedingText)
        case .minimalInline: body = minimalInlinePrompt(from: precedingText)
        case .gemmaChat:     body = gemmaAutocompletePrompt(from: precedingText)
        }
        return instructionsHead(instructions) + body
    }

    /// Голова с пользовательскими указаниями. Статична per-сессия (меняется только при правке
    /// настроек) -> KV-prefix остаётся валидным между нажатиями. Пусто/пробелы -> "".
    public static func instructionsHead(_ instructions: String) -> String {
        let t = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : "Указания (соблюдай при продолжении): \(t)\n\n"
    }

    /// .plain raw: недавний хвост БЕЗ обрезки trailing-пробелов (бриф просит этот вариант).
    public static func plainRawPrompt(from precedingText: String, maxChars: Int = 1200) -> String {
        precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
    }

    /// Минимальная инлайн-инструкция одной строкой + текст (trailing-WS обрезан).
    public static func minimalInlinePrompt(from precedingText: String, maxChars: Int = 600) -> String {
        var tail = precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
        while let last = tail.last, last == " " || last == "\n" || last == "\t" { tail.removeLast() }
        return "Продолжи текст коротко тем же языком: \(tail)"
    }

    /// Выбор prompt-режима для inline autocomplete.
    /// Gemma i1 - instruction-tuned; голый continuation часто дрейфует по языку/задаче.
    /// Для неё используем turn-format, но всё равно через `.plain`, чтобы сохранить
    /// низкоуровневый BOS/KV-reuse путь LocalLLMClient.
    public static func autocompletePrompt(from precedingText: String, modelFileName: String,
                                          maxChars: Int = 1200) -> String {
        if modelFileName.lowercased().contains("gemma") {
            return gemmaAutocompletePrompt(from: precedingText, maxChars: maxChars)
        }
        return completionPrompt(from: precedingText, maxChars: maxChars)
    }

    /// Промпт в формате Gemma-чата для осмысленного автокомплита: инструкция + текст в
    /// user-ходе, продолжение генерируется в model-ходе. BOS добавляет .plain-режим клиента.
    /// Инструкция держит язык/стиль текста (главная жалоба - сполз в другой язык).
    public static func chatPrompt(from precedingText: String, maxChars: Int = 600) -> String {
        let tail = precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
        return "<start_of_turn>user\nContinue the text below. Output ONLY the next 2-6 words, in the SAME language and style as the text. No explanation, no translation, no quotes.\n\n\(tail)<end_of_turn>\n<start_of_turn>model\n"
    }

    /// Gemma-specific prompt для автодополнения именно текста после каретки.
    /// Требуем вернуть точную строку для вставки: с ведущим пробелом, если он нужен,
    /// либо суффикс текущего слова, если пользователь печатает внутри слова.
    public static func gemmaAutocompletePrompt(from precedingText: String, maxChars: Int = 1200) -> String {
        let tail = precedingText.count > maxChars ? String(precedingText.suffix(maxChars)) : precedingText
        let language = languageHint(for: tail)
        return """
        <start_of_turn>user
        You are an inline autocomplete engine for macOS typing.
        Return ONLY the exact text to insert after the cursor.
        Continue with the next 1 to 6 words, in \(language), preserving the same tone and style.
        If the continuation starts a new word, include the leading space. If completing the current word, return only the missing suffix.
        Do not explain, translate, quote, answer questions, or change topic.

        Text before cursor:
        \(tail)<end_of_turn>
        <start_of_turn>model
        """
    }

    private static func languageHint(for text: String) -> String {
        switch TextScriptDetector.dominant(of: String(text.suffix(120))) {
        case .cyrillic:
            return "Russian"
        case .latin:
            return "English"
        case .neutral:
            return "the same language as the text"
        }
    }
}
