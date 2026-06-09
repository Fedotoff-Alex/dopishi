import Foundation

public enum RepetitionGuard {
    /// Очистить подсказку от повторов. Вернуть nil, если показывать нечего
    /// (пусто или чистое эхо хвоста контекста).
    public static func filter(suggestion: String, context: String) -> String? {
        let collapsed = collapseImmediateRepeat(suggestion)
        guard !collapsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if isEcho(of: context, suggestion: collapsed) { return nil }
        if isFoldedTrailingDuplicate(suggestion: collapsed, context: context) { return nil }
        if looksLikeLoop(collapsed) { return nil }
        return collapsed
    }

    /// Схлопнуть немедленный повтор по словам: если последовательность слов целиком состоит
    /// из повторов наименьшего периода (напр. "X Y X Y" или "да да да"), оставить один период.
    static func collapseImmediateRepeat(_ s: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let n = words.count
        guard n >= 2 else { return s }
        for p in 1...(n / 2) where n % p == 0 {
            let unit = Array(words[0..<p])
            var i = p
            var isRepeat = true
            while i < n {
                if Array(words[i..<(i + p)]) != unit { isRepeat = false; break }
                i += p
            }
            if isRepeat { return unit.joined(separator: " ") }
        }
        return s
    }

    /// Подсказка - чистое эхо хвоста контекста (нормализованное совпадение по словам).
    static func isEcho(of context: String, suggestion: String) -> Bool {
        let ctx = normalizedWords(context)
        let sug = normalizedWords(suggestion)
        guard !sug.isEmpty, sug.count <= ctx.count else { return false }
        return Array(ctx.suffix(sug.count)) == sug
    }

    /// Folded-проверка trailing-дубля (подсказка не повторяет хвост уже набранного).
    /// Ловит случаи, когда подсказка дублирует хвост контекста с отличием в регистре/пунктуации.
    /// Минимум 3 folded-символа, чтобы не подавлять короткие совпадения случайно.
    static func isFoldedTrailingDuplicate(suggestion: String, context: String) -> Bool {
        let foldedSug = TextFold.folded(suggestion)
        guard foldedSug.count >= 3 else { return false }

        // Хвост контекста - те же символы по длине подсказки (с запасом x2 для надёжности)
        let ctxSuffix = String(context.suffix(suggestion.count * 2 + 20))
        let foldedCtx = TextFold.folded(ctxSuffix)
        guard !foldedCtx.isEmpty else { return false }

        // Сценарий 1: подсказка является началом того, что уже есть после каретки (контекст содержит подсказку как префикс)
        if foldedCtx.hasPrefix(foldedSug) { return true }

        // Сценарий 2: подсказка содержит весь хвост контекста (подсказка = хвост + ещё что-то)
        if foldedSug.hasPrefix(foldedCtx), foldedCtx.count >= 3 { return true }

        // Сценарий 3: длинный общий префикс (>= половины подсказки и >= 3 символов)
        let overlap = commonFoldedPrefixLength(foldedSug, foldedCtx)
        return overlap >= max(3, foldedSug.count / 2)
    }

    /// Длина общего folded-префикса двух строк.
    private static func commonFoldedPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var li = lhs.startIndex
        var ri = rhs.startIndex
        while li < lhs.endIndex, ri < rhs.endIndex, lhs[li] == rhs[ri] {
            count += 1
            li = lhs.index(after: li)
            ri = rhs.index(after: ri)
        }
        return count
    }

    /// Похоже на залипание: одна БУКВА/ЦИФРА подряд >= 5 раз (напр. "20000000..."),
    /// что наш пословный схлоп не ловит (нет пробелов). Пунктуацию НЕ считаем -
    /// "!!!!!", "....." (эллипсис), длинные тире/подчёркивания легитимны.
    static func looksLikeLoop(_ s: String) -> Bool {
        let chars = Array(s)
        guard chars.count >= 5 else { return false }
        var run = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1], chars[i].isLetter || chars[i].isNumber {
                run += 1
                if run >= 5 { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    private static func normalizedWords(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
