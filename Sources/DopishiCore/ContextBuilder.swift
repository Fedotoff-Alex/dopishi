import Foundation

/// Собирает финальный промпт из каналов контекста под бюджет символов (прокси токенов).
///
/// KV-ИНВАРИАНТ (критично для скорости): статический few-shot префикс остаётся ЛИТЕРАЛЬНОЙ
/// головой промпта, чтобы KV prefix-reuse переиспользовал его декод. OCR-текст вставляется
/// ПОСЛЕ головы, строкой "Окно: <text>" внутри последнего few-shot примера ПЕРЕД "Текст:" -
/// то есть в динамической части, которую и так декодируем заново. Никогда не ставить OCR
/// перед головой - иначе prefix-reuse = 0 и prefill всего промпта на каждой генерации.
public enum ContextBuilder {
    /// tailMax - бюджет хвоста поля (важнее), ocrMax - бюджет OCR (режется первым).
    /// instructions - опц. пользовательские указания в статическую голову (KV-голова цела).
    public static func build(_ bundle: ContextBundle, tailMax: Int = 600, ocrMax: Int = 600,
                             clipMax: Int = 600, memMax: Int = 600, instructions: String = "") -> String {
        let head = PromptBuilder.instructionsHead(instructions)
        var tail = bundle.fieldTail.count > tailMax
            ? String(bundle.fieldTail.suffix(tailMax)) : bundle.fieldTail
        while let last = tail.last, last == " " || last == "\n" || last == "\t" { tail.removeLast() }

        // Каналы: схлопнутые в одну строку, обрезанные под бюджет.
        // ВОРОНКА 2 (D-03/D-04): доп-канал с секретом дропается ЦЕЛИКОМ. fieldTail (хвост поля,
        // что пользователь печатает сам) под guard НЕ ставим - Open Q1 (иначе теряем подсказки).
        let mem = bundle.memory.flatMap { SecretGuard.looksSecret($0) ? nil : collapse($0, max: memMax) } ?? ""
        let win = bundle.ocr.flatMap { SecretGuard.looksSecret($0.windowText) ? nil : collapse($0.windowText, max: ocrMax) } ?? ""
        let clip = bundle.clipboard.flatMap { SecretGuard.looksSecret($0) ? nil : collapse($0, max: clipMax) } ?? ""

        // Нет ни одного доп. канала - ровно как fewShotCompletionPrompt (полная KV-голова, 0 регрессии).
        guard !mem.isEmpty || !win.isEmpty || !clip.isEmpty else {
            return head + PromptBuilder.fewShotPrefix + " " + tail + "\nПродолжение:"
        }

        // Доп. каналы - в ДИНАМИЧЕСКОЙ зоне (после статической головы, перед "Текст:"), KV-safe.
        // Память (история диалога) - первой как фон, затем экран, затем буфер.
        var dynamic = ""
        if !mem.isEmpty { dynamic += "Память: " + mem + "\n" }
        if !win.isEmpty { dynamic += "Окно: " + win + "\n" }
        if !clip.isEmpty { dynamic += "Буфер: " + clip + "\n" }
        return head + PromptBuilder.fewShotPrefixWithoutLastTextLabel
            + dynamic + "Текст: " + tail + "\nПродолжение:"
    }

    /// Канал в одну строку: схлоп переносов/двойных пробелов, трим, обрезка под бюджет.
    private static func collapse(_ s: String, max: Int) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.count > max { t = String(t.prefix(max)) }
        return t
    }
}
