import Foundation

/// Обрезает utf16-слайс строки до ближайших валидных grapheme-границ (D-06).
/// start: если не на границе - смещаем ВПЕРЁД (сохраняем правый конец окна, ближе к каретке).
/// end: если не на границе - смещаем НАЗАД (не включаем неполный grapheme).
/// Возвращает (sanitizedSlice, adjustedWindowStart) для пересчёта offset = caret - adjustedStart.
public enum WindowSanitizer {
    public static func sanitize(
        _ text: String,
        utf16Start: Int,
        utf16End: Int
    ) -> (slice: String, adjustedStart: Int) {
        let utf16 = text.utf16
        guard utf16Start >= 0, utf16Start < utf16End, utf16End <= utf16.count else {
            return ("", utf16Start)
        }
        var s = utf16Start
        while s < utf16End {
            let idx = utf16.index(utf16.startIndex, offsetBy: s)
            if String.Index(idx, within: text) != nil { break }
            s += 1
        }
        var e = utf16End
        while e > s {
            let idx = utf16.index(utf16.startIndex, offsetBy: e)
            if String.Index(idx, within: text) != nil { break }
            e -= 1
        }
        guard s < e,
              let si = String.Index(utf16.index(utf16.startIndex, offsetBy: s), within: text),
              let ei = String.Index(utf16.index(utf16.startIndex, offsetBy: e), within: text)
        else { return ("", s) }
        return (String(text[si..<ei]), s)
    }

    /// D-06: дропает возможно-неполный первый/последний grapheme cluster при разрезе не от края текста.
    /// - cutAtStart: рез НЕ у начала полного текста - первый grapheme может быть неполным, дропаем.
    /// - cutAtEnd: рез НЕ у конца полного текста - последний grapheme может быть неполным, дропаем.
    /// Также дропает U+FFFD на краях (AX-bridge заменяет unpaired surrogates на U+FFFD; краевой
    /// U+FFFD тоже является артефактом разрезания).
    /// Возвращает (обрезанный_слайс, droppedStartUTF16) - количество UTF-16 единиц, отброшенных
    /// с начала. Используется для пересчёта windowAdjustedStart.
    public static func dropEdgeClusters(
        _ slice: String,
        cutAtStart: Bool,
        cutAtEnd: Bool
    ) -> (slice: String, droppedStartUTF16: Int) {
        var result = slice
        var droppedStart = 0

        if cutAtStart, !result.isEmpty {
            let firstChar = result[result.startIndex]
            let firstUTF16Count = firstChar.utf16.count
            result = String(result[result.index(after: result.startIndex)...])
            droppedStart = firstUTF16Count
        }

        if cutAtEnd, !result.isEmpty {
            result = String(result[..<result.index(before: result.endIndex)])
        }

        return (result, droppedStart)
    }
}
